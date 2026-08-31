`timescale 1ns / 1ps
//
// Testbench for the Stage-B pipelined cpu.v (Stage A's structural pipeline
// plus stall-only hazard detection: comparator on destination registers of
// whatever is in Compute/Memory/Writeback vs. the source registers being
// read in Decode; on a match, freeze PC/IR and inject a bubble into B2).
//
// Same per-cycle checking style as tb_cpu_stageA.v (PC/IR now latch
// conditionally on !stall, but cpu_out still changes basically every cycle,
// so this still checks every clock edge against a precomputed value rather
// than a change-log). Also checks `stall` itself at every cycle, and the
// final register file, so a wrong stall DURATION or a wrong final VALUE
// both get caught, not just one or the other.
//
// Test program exercises two different hazard shapes, plus a couple of
// independent instructions that must NOT get spuriously stalled:
//
//   mem[0] = 0x0481   ADD R1, R0, 1      producer P1
//   mem[1] = 0x0110   ADD R2, R1, R0     consumer C1, gap=0 (immediately
//                                        after P1) -> expect a 3-cycle stall
//                                        (P1 has to clear Compute, Memory,
//                                        AND Writeback before C1 can read R1)
//   mem[2] = 0x0583   ADD R3, R0, 3      independent -- must not stall
//   mem[3] = 0x0604   ADD R4, R0, 4      producer P2
//   mem[4] = 0x0685   ADD R5, R0, 5      independent, fills the 1-instruction
//                                        gap between P2 and its consumer
//   mem[5] = 0x0340   ADD R6, R4, R0     consumer C2, gap=1 -> expect only a
//                                        2-cycle stall (one fewer than C1,
//                                        since P2 already got one cycle of
//                                        head start from R5 being fetched
//                                        in between)
//   mem[6..] = 0x4380 HALT, padded
//
// NOTE: you will see `stall` come back high for cycles 1-3 even though
// nothing in this program should hazard against anything yet. That is not
// a bug in your hazard logic -- IR resets to 16'h0000, which this ISA
// decodes as a legitimate (if accidental) "ADD R0, R0, R0" instruction
// (op_code 00 always means ALU, and there's no true NOP encoding). That
// phantom instruction rides through _ex/_mem/_wb for the first few cycles
// and registers as a hazard against P1's read of R0, costing a harmless
// one-time 3-cycle startup stall. It doesn't corrupt any result (R0 stays
// 0 either way), so the golden trace below simply includes it as expected
// behavior of this design rather than treating it as an error.
//
module cpu_stageB_tb;

    reg clk;
    reg reset;
    wire [47:0] cpu_out;
    wire        halt;
    integer i;

    localparam NUM_CYCLES = 20;

    cpu dut (
        .clk(clk),
        .reset(reset),
        .cpu_out(cpu_out),
        .halt(halt)
    );

    initial begin
        dut.imem_inst.mem[0] = 16'h0481; // ADD R1, R0, 1
        dut.imem_inst.mem[1] = 16'h0110; // ADD R2, R1, R0
        dut.imem_inst.mem[2] = 16'h0583; // ADD R3, R0, 3
        dut.imem_inst.mem[3] = 16'h0604; // ADD R4, R0, 4
        dut.imem_inst.mem[4] = 16'h0685; // ADD R5, R0, 5
        dut.imem_inst.mem[5] = 16'h0340; // ADD R6, R4, R0
        dut.imem_inst.mem[6] = 16'h4380; // HALT
        for (i = 7; i < 24; i = i + 1)
            dut.imem_inst.mem[i] = 16'h4380; // padding
    end

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Golden per-cycle trace, captured from a known-correct Stage-B
    // reference and hand-checked (stall durations of 3 and 2 cycles for
    // the gap-0 and gap-1 hazards respectively, independent instructions
    // passing through with no extra stall).
    reg [47:0] expected      [0:20];
    reg        expected_stall[0:20];

    initial begin
        expected[0]  = 48'h000000000000; expected_stall[0]  = 1'b0; // post-reset
        expected[1]  = 48'h000104810000; expected_stall[1]  = 1'b1; // startup phantom-hazard stall
        expected[2]  = 48'h000104810000; expected_stall[2]  = 1'b1;
        expected[3]  = 48'h000104810000; expected_stall[3]  = 1'b1;
        expected[4]  = 48'h000104810000; expected_stall[4]  = 1'b0;
        expected[5]  = 48'h000201100000; expected_stall[5]  = 1'b1; // C1 stalling on P1 (gap=0)
        expected[6]  = 48'h000201100001; expected_stall[6]  = 1'b1;
        expected[7]  = 48'h000201100000; expected_stall[7]  = 1'b1;
        expected[8]  = 48'h000201100000; expected_stall[8]  = 1'b0;
        expected[9]  = 48'h000305830000; expected_stall[9]  = 1'b0; // independent, no stall
        expected[10] = 48'h000406040001; expected_stall[10] = 1'b0;
        expected[11] = 48'h000506850003; expected_stall[11] = 1'b0;
        expected[12] = 48'h000603400004; expected_stall[12] = 1'b1; // C2 stalling on P2 (gap=1)
        expected[13] = 48'h000603400005; expected_stall[13] = 1'b1;
        expected[14] = 48'h000603400000; expected_stall[14] = 1'b0;
        expected[15] = 48'h000743800000; expected_stall[15] = 1'b0;
        expected[16] = 48'h000843800004; expected_stall[16] = 1'b0;
        expected[17] = 48'h000943800000; expected_stall[17] = 1'b0;
        expected[18] = 48'h000a43800000; expected_stall[18] = 1'b0;
        expected[19] = 48'h000b43800000; expected_stall[19] = 1'b0;
        expected[20] = 48'h000c43800000; expected_stall[20] = 1'b0;
    end

    reg [15:0] expected_regs [0:7];
    initial begin
        expected_regs[0] = 16'h0000;
        expected_regs[1] = 16'h0001;
        expected_regs[2] = 16'h0001; // R2 = R1 (the hazard was resolved correctly)
        expected_regs[3] = 16'h0003;
        expected_regs[4] = 16'h0004;
        expected_regs[5] = 16'h0005;
        expected_regs[6] = 16'h0004; // R6 = R4 (the gap=1 hazard was resolved correctly)
        expected_regs[7] = 16'h0000;
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
            $display("ALL CHECKS PASSED -- tb_cpu_stageB looks correct (per-cycle cpu_out + stall trace, final register file)");
        else
            $display("%0d ERROR(S) FOUND", errors);

        $finish;
    end

endmodule