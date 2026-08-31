`timescale 1ns / 1ps
//
// Testbench for the Stage-D pipelined cpu.v (Stage C's Memory-to-Compute
// forwarding plus "Write-back to Compute" forwarding: a producer sitting
// in Writeback forwards its RW result into the ALU operand muxes of
// whatever's now in Compute).
//
// Checks cpu_out, stall, fwd_mem_a, fwd_mem_b, fwd_wb_a, and fwd_wb_b every
// cycle against a precomputed golden trace, plus the final register file.
//
// Test program exercises all four hazard shapes this design now handles
// differently:
//
//   mem[0..2]  = 0x0787   ADD R7, R0, 7 (x3)   warm-up (drain reset phantom)
//   mem[3]     = 0x0481   ADD R1, R0, 1        P1 (Test A: gap=0 ALU)
//   mem[4]     = 0x0110   ADD R2, R1, R0       C1 -- still 0 stall (Stage C,
//                          unaffected by Stage D's changes)
//   mem[5]     = 0x0604   ADD R4, R0, 4        P2 (Test B: gap=1 ALU)
//   mem[6]     = 0x0685   ADD R5, R0, 5        filler
//   mem[7]     = 0x0340   ADD R6, R4, R0       C2 -- NOW 0 stall (was 2 in
//                          Stage B/C), resolved by fwd_wb_a
//   mem[8]     = 0x8580   LOAD R3, [R0+0]      P3 (Test C: gap=0 LOAD)
//   mem[9]     = 0x03B0   ADD R7, R3, R0       C3 -- exactly 1 mandatory
//                          stall cycle (is_load_ex), then resolved by
//                          fwd_wb_a once P3 reaches Writeback
//   mem[10]    = 0x0486   ADD R1, R0, 6        P4 (Test D: gap=2)
//   mem[11]    = 0x0685   ADD R5, R0, 5        filler1
//   mem[12]    = 0x0706   ADD R6, R0, 6        filler2
//   mem[13]    = 0x0110   ADD R2, R1, R0       C4 -- exactly 1 stall cycle
//                          (same-cycle register-file read/write collision
//                          guard) and NO forwarding fires -- by the time C4
//                          re-reads in Decode, P4's write has already
//                          landed in the register file, so the plain
//                          read is already correct.
//   mem[14..]  = 0x4380   HALT, padded
//
// data_mem[0] is preloaded with 0x00AA for P3 to load.
//
module cpu_stageD_tb;

    reg clk;
    reg reset;
    wire [47:0] cpu_out;
    wire        halt;
    integer i;

    localparam NUM_CYCLES = 25;

    cpu dut (
        .clk(clk),
        .reset(reset),
        .cpu_out(cpu_out),
        .halt(halt)
    );

    initial begin
        dut.imem_inst.mem[0]  = 16'h0787; // ADD R7, R0, 7   warm-up
        dut.imem_inst.mem[1]  = 16'h0787; // ADD R7, R0, 7   warm-up
        dut.imem_inst.mem[2]  = 16'h0787; // ADD R7, R0, 7   warm-up
        dut.imem_inst.mem[3]  = 16'h0481; // ADD R1, R0, 1
        dut.imem_inst.mem[4]  = 16'h0110; // ADD R2, R1, R0
        dut.imem_inst.mem[5]  = 16'h0604; // ADD R4, R0, 4
        dut.imem_inst.mem[6]  = 16'h0685; // ADD R5, R0, 5
        dut.imem_inst.mem[7]  = 16'h0340; // ADD R6, R4, R0
        dut.imem_inst.mem[8]  = 16'h8580; // LOAD R3, [R0+0]
        dut.imem_inst.mem[9]  = 16'h03B0; // ADD R7, R3, R0
        dut.imem_inst.mem[10] = 16'h0486; // ADD R1, R0, 6
        dut.imem_inst.mem[11] = 16'h0685; // ADD R5, R0, 5
        dut.imem_inst.mem[12] = 16'h0706; // ADD R6, R0, 6
        dut.imem_inst.mem[13] = 16'h0110; // ADD R2, R1, R0
        dut.imem_inst.mem[14] = 16'h4380; // HALT
        for (i = 15; i < 32; i = i + 1)
            dut.imem_inst.mem[i] = 16'h4380; // padding

        dut.dmem_inst.mem[0] = 16'h00AA; // value P3 will load
    end

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Golden per-cycle trace, captured from a known-correct Stage-D
    // reference (built from your draft after the three fixes) and
    // hand-checked at every key transition described above.
    reg [47:0] expected        [0:25];
    reg        expected_stall  [0:25];
    reg        expected_fwd_ma [0:25];
    reg        expected_fwd_mb [0:25];
    reg        expected_fwd_wa [0:25];
    reg        expected_fwd_wb [0:25];

    task set_row;
        input integer idx;
        input [47:0] cpu_out_val;
        input        stall_val, fma, fmb, fwa, fwb;
        begin
            expected[idx]        = cpu_out_val;
            expected_stall[idx]  = stall_val;
            expected_fwd_ma[idx] = fma;
            expected_fwd_mb[idx] = fmb;
            expected_fwd_wa[idx] = fwa;
            expected_fwd_wb[idx] = fwb;
        end
    endtask

    initial begin
        set_row(0,  48'h000000000000, 0, 0, 0, 0, 0);
        set_row(1,  48'h000107870000, 0, 0, 0, 0, 0);
        set_row(2,  48'h000207870000, 0, 1, 0, 0, 0);
        set_row(3,  48'h000307870007, 1, 0, 0, 1, 0);
        set_row(4,  48'h000307870007, 1, 0, 0, 0, 0);
        set_row(5,  48'h000307870000, 1, 0, 0, 0, 0);
        set_row(6,  48'h000307870000, 0, 0, 0, 0, 0);
        set_row(7,  48'h000404810007, 0, 0, 0, 0, 0);
        set_row(8,  48'h000501100007, 0, 0, 0, 0, 0);
        set_row(9,  48'h000606040001, 0, 1, 0, 0, 0);
        set_row(10, 48'h000706850001, 0, 0, 0, 0, 0);
        set_row(11, 48'h000803400004, 0, 0, 0, 0, 0);
        set_row(12, 48'h000985800005, 0, 0, 0, 1, 0); // gap=1 ALU resolved with zero stall
        set_row(13, 48'h000a03b00004, 1, 0, 0, 0, 0); // gap=0 LOAD: mandatory 1-cycle stall
        set_row(14, 48'h000a03b00000, 0, 0, 0, 0, 0);
        set_row(15, 48'h000b04860000, 0, 0, 0, 1, 0); // load's value forwarded from Writeback
        set_row(16, 48'h000c068500aa, 0, 0, 0, 0, 0);
        set_row(17, 48'h000d07060006, 0, 0, 0, 0, 0);
        set_row(18, 48'h000e01100005, 1, 0, 0, 0, 0); // gap=2: same-cycle regfile collision guard
        set_row(19, 48'h000e01100006, 0, 0, 0, 0, 0); // no forwarding needed here -- plain read now correct
        set_row(20, 48'h000f43800001, 0, 0, 0, 0, 0);
        set_row(21, 48'h001043800006, 0, 0, 0, 0, 0);
        set_row(22, 48'h001143800000, 0, 0, 0, 0, 0);
        set_row(23, 48'h001243800000, 0, 0, 0, 0, 0);
        set_row(24, 48'h001343800000, 0, 0, 0, 0, 0);
        set_row(25, 48'h001443800000, 0, 0, 0, 0, 0);
    end

    reg [15:0] expected_regs [0:7];
    initial begin
        expected_regs[0] = 16'h0000;
        expected_regs[1] = 16'h0006;
        expected_regs[2] = 16'h0006;
        expected_regs[3] = 16'h00aa;
        expected_regs[4] = 16'h0004;
        expected_regs[5] = 16'h0005;
        expected_regs[6] = 16'h0006;
        expected_regs[7] = 16'h00aa;
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
        halt_seen_at = -1;

        if (cpu_out !== expected[0]) begin
            errors = errors + 1;
            $display("FAIL cyc 0: got cpu_out=%h expected %h (post-reset state)", cpu_out, expected[0]);
        end

        for (cyc = 1; cyc <= NUM_CYCLES; cyc = cyc + 1) begin
            @(posedge clk);
            #1;

            if (cpu_out !== expected[cyc]) begin
                errors = errors + 1;
                $display("FAIL cyc %0d: got cpu_out=%h expected %h", cyc, cpu_out, expected[cyc]);
            end
            if (dut.stall !== expected_stall[cyc]) begin
                errors = errors + 1;
                $display("FAIL cyc %0d: got stall=%b expected %b", cyc, dut.stall, expected_stall[cyc]);
            end
            if (dut.fwd_mem_a !== expected_fwd_ma[cyc]) begin
                errors = errors + 1;
                $display("FAIL cyc %0d: got fwd_mem_a=%b expected %b", cyc, dut.fwd_mem_a, expected_fwd_ma[cyc]);
            end
            if (dut.fwd_mem_b !== expected_fwd_mb[cyc]) begin
                errors = errors + 1;
                $display("FAIL cyc %0d: got fwd_mem_b=%b expected %b", cyc, dut.fwd_mem_b, expected_fwd_mb[cyc]);
            end
            if (dut.fwd_wb_a !== expected_fwd_wa[cyc]) begin
                errors = errors + 1;
                $display("FAIL cyc %0d: got fwd_wb_a=%b expected %b", cyc, dut.fwd_wb_a, expected_fwd_wa[cyc]);
            end
            if (dut.fwd_wb_b !== expected_fwd_wb[cyc]) begin
                errors = errors + 1;
                $display("FAIL cyc %0d: got fwd_wb_b=%b expected %b", cyc, dut.fwd_wb_b, expected_fwd_wb[cyc]);
            end

            if (halt && halt_seen_at == -1) begin
                halt_seen_at = cyc;
                $display("INFO: halt first asserted at cyc %0d", cyc);
            end
        end

        if (halt_seen_at == -1) begin
            errors = errors + 1;
            $display("FAIL: halt never asserted within %0d cycles", NUM_CYCLES);
        end

        for (i = 0; i < 8; i = i + 1) begin
            if (dut.rf_inst.registers[i] !== expected_regs[i]) begin
                errors = errors + 1;
                $display("FAIL: R%0d = %h, expected %h", i, dut.rf_inst.registers[i], expected_regs[i]);
            end
        end

        if (errors == 0)
            $display("ALL CHECKS PASSED -- tb_cpu_stageD looks correct (per-cycle cpu_out/stall/forwarding trace, final register file)");
        else
            $display("%0d ERROR(S) FOUND", errors);

        $finish;
    end

endmodule