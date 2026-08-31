`timescale 1ns / 1ps
//
// Testbench for the Stage-A pipelined cpu.v (structural 5-stage pipeline,
// no hazard handling yet -- every buffer latches unconditionally every
// cycle). This is NOT the same style of testbench as Tasks 1-5.
//
// Why this had to change from the old "change-log" style:
//   - Previously, cpu_out only produced a new row when it actually changed,
//     because the multicycle FSM only pulsed pc_we/ir_we/rz_we on specific
//     states. In Stage A, PC and IR latch every single cycle unconditionally,
//     so cpu_out is GUARANTEED to change every cycle. A change-log golden
//     trace doesn't even make sense here -- this testbench instead checks
//     cpu_out against a precomputed expected value on EVERY clock edge.
//   - `halt` also no longer means "the machine is done". It now only means
//     "the halt instruction (0x4380) has been fetched into IR" -- at that
//     moment there can still be up to 4 older instructions in flight
//     (Decode/Execute/Memory/Writeback). This testbench does NOT stop the
//     instant halt goes high; it runs a fixed number of cycles chosen to
//     cover the full drain, then separately checks the register file.
//
// Test program: 7 independent ADD-immediate instructions, each writing a
// DISTINCT destination register (R1..R7) and reading only R0 as a source
// (R0 is never written by this program, and stays 0 from reset). This
// guarantees zero data hazards of any kind -- including the same-cycle
// register-file write/read collision that Stage A doesn't handle yet
// (that's a Stage B concern). The tail of instruction memory is padded
// with extra copies of the HALT instruction so that PC running past the
// end of the program (Stage A never stops fetching) doesn't read
// uninitialized ('x') instruction memory and drag IR/halt to 'x'.
//
//   mem[0] = 0x0481   ADD R1, R0, 1
//   mem[1] = 0x0502   ADD R2, R0, 2
//   mem[2] = 0x0583   ADD R3, R0, 3
//   mem[3] = 0x0604   ADD R4, R0, 4
//   mem[4] = 0x0685   ADD R5, R0, 5
//   mem[5] = 0x0706   ADD R6, R0, 6
//   mem[6] = 0x0787   ADD R7, R0, 7
//   mem[7..15] = 0x4380   HALT (BEQ -1, R0, R0), padding
//
module cpu_stageA_tb;

    reg clk;
    reg reset;
    wire [47:0] cpu_out;
    wire        halt;
    integer i;

    localparam NUM_CYCLES = 16; // enough to fetch all 8 real instructions
                                 // (cycles 1-8) and drain the last one
                                 // (ADD R7) all the way to Writeback

    // NOTE: change "cpu" here if you rename/re-case your top module.
    cpu dut (
        .clk(clk),
        .reset(reset),
        .cpu_out(cpu_out),
        .halt(halt)
    );

    initial begin
        dut.imem_inst.mem[0] = 16'h0481; // ADD R1, R0, 1
        dut.imem_inst.mem[1] = 16'h0502; // ADD R2, R0, 2
        dut.imem_inst.mem[2] = 16'h0583; // ADD R3, R0, 3
        dut.imem_inst.mem[3] = 16'h0604; // ADD R4, R0, 4
        dut.imem_inst.mem[4] = 16'h0685; // ADD R5, R0, 5
        dut.imem_inst.mem[5] = 16'h0706; // ADD R6, R0, 6
        dut.imem_inst.mem[6] = 16'h0787; // ADD R7, R0, 7
        for (i = 7; i < 16; i = i + 1)
            dut.imem_inst.mem[i] = 16'h4380; // HALT, padding
    end

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Golden per-cycle trace of cpu_out = {PC, IR, RZ}, one entry per
    // clock edge including the post-reset sample at index 0. Captured
    // from a known-correct Stage-A reference (properly chained
    // _ex -> _mem -> _wb latches) and hand-checked against the encodings
    // above.
    reg [47:0] expected [0:16];

    initial begin
        expected[0]  = 48'h000000000000; // post-reset
        expected[1]  = 48'h000104810000;
        expected[2]  = 48'h000205020000;
        expected[3]  = 48'h000305830001;
        expected[4]  = 48'h000406040002;
        expected[5]  = 48'h000506850003;
        expected[6]  = 48'h000607060004;
        expected[7]  = 48'h000707870005;
        expected[8]  = 48'h000843800006;
        expected[9]  = 48'h000943800007;
        expected[10] = 48'h000a43800000;
        expected[11] = 48'h000b43800000;
        expected[12] = 48'h000c43800000;
        expected[13] = 48'h000d43800000;
        expected[14] = 48'h000e43800000;
        expected[15] = 48'h000f43800000;
        expected[16] = 48'h001043800000;
    end

    // Expected final register-file contents once every instruction has
    // reached Writeback. This is the check that actually exercises
    // addr_c_wb/writes_back_wb -- cpu_out alone (PC/IR/RZ) never looks at
    // the register file, so a bug in how the destination-register address
    // is staged from Decode through to Writeback would NOT show up in the
    // per-cycle cpu_out trace above, only here.
    reg [15:0] expected_regs [0:7];

    initial begin
        expected_regs[0] = 16'h0000; // R0 must stay untouched
        expected_regs[1] = 16'h0001;
        expected_regs[2] = 16'h0002;
        expected_regs[3] = 16'h0003;
        expected_regs[4] = 16'h0004;
        expected_regs[5] = 16'h0005;
        expected_regs[6] = 16'h0006;
        expected_regs[7] = 16'h0007;
    end

    integer errors;
    integer cyc;
    integer halt_seen_at;

    initial begin
        reset = 1'b1;
        @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        errors = 0;
        cyc = 0;
        halt_seen_at = -1;

        if (cpu_out !== expected[0]) begin
            errors = errors + 1;
            $display("FAIL cyc %0d: got cpu_out=%h expected %h (post-reset state)", cyc, cpu_out, expected[0]);
        end

        for (cyc = 1; cyc <= NUM_CYCLES; cyc = cyc + 1) begin
            @(posedge clk);
            #1; // let combinational logic (halt, cpu_out) settle

            if (cpu_out !== expected[cyc]) begin
                errors = errors + 1;
                $display("FAIL cyc %0d: got cpu_out=%h expected %h", cyc, cpu_out, expected[cyc]);
            end

            if (halt && halt_seen_at == -1) begin
                halt_seen_at = cyc;
                $display("INFO: halt first asserted at cyc %0d (HALT fetched into IR) -- pipeline not drained yet", cyc);
            end
        end

        if (halt_seen_at == -1) begin
            errors = errors + 1;
            $display("FAIL: halt never asserted within %0d cycles", NUM_CYCLES);
        end

        // By now every instruction, including the last ADD (R7), must have
        // reached Writeback and updated the register file.
        for (i = 0; i < 8; i = i + 1) begin
            if (dut.rf_inst.registers[i] !== expected_regs[i]) begin
                errors = errors + 1;
                $display("FAIL: R%0d = %h, expected %h", i, dut.rf_inst.registers[i], expected_regs[i]);
            end
        end

        if (errors == 0)
            $display("ALL CHECKS PASSED -- tb_cpu_stageA looks correct (per-cycle cpu_out trace + final register file)");
        else
            $display("%0d ERROR(S) FOUND", errors);

        $finish;
    end

endmodule