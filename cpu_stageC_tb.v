`timescale 1ns / 1ps
//
// Testbench for the Stage-C pipelined cpu.v (Stage B's stall-only hazard
// detection plus "Memory to Compute" forwarding: an ALU-producing
// instruction sitting in Memory forwards its RZ result directly into the
// ALU operand muxes of whatever's now in Compute, instead of making that
// consumer stall).
//
// Same per-cycle checking style as tb_cpu_stageA.v / tb_cpu_stageB.v.
// Also checks `stall`, `fwd_mem_a`, and `fwd_mem_b` every cycle, so both
// the timing improvement AND the actual forwarding activation get
// verified, not just the eventual register values.
//
// Test program, in order:
//   mem[0..2] = 0x0787  ADD R7, R0, 7 (x3)   warm-up -- lets the reset-value
//                        "phantom ADD R0,R0,R0" instruction (IR resets to
//                        0x0000, which this ISA decodes as a legitimate,
//                        if accidental, ALU op writing R0 -- see the Stage
//                        B testbench comments) fully drain out of the
//                        pipeline before the real hazard test below, so
//                        that test isn't muddied by incidental interaction
//                        with pipeline fill.
//   mem[3] = 0x0481     ADD R1, R0, 1        producer P1
//   mem[4] = 0x0110     ADD R2, R1, R0       consumer C1, gap=0 -- with
//                        Stage B alone this cost 3 stall cycles; with
//                        Memory-to-Compute forwarding it should now cost
//                        ZERO stall cycles, with fwd_mem_a activating
//                        instead once P1 reaches Memory.
//   mem[5] = 0x0583     ADD R3, R0, 3        independent
//   mem[6] = 0x0604     ADD R4, R0, 4        producer P2
//   mem[7] = 0x0685     ADD R5, R0, 5        independent (gap filler)
//   mem[8] = 0x0340     ADD R6, R4, R0       consumer C2, gap=1 -- forwarding
//                        does NOT cover this shape yet (that's Stage D),
//                        so this should still cost 2 stall cycles, same as
//                        Stage B.
//   mem[9..] = 0x4380   HALT, padded
//
// Run with, e.g.:
//   iverilog -o cpu_tb.vvp alu.v registerfile.v ins_mem.v data_mem.v condition_encoding.v cpu.v tb_cpu_stageC.v
//   vvp cpu_tb.vvp
//
module cpu_stageC_tb;

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
        dut.imem_inst.mem[0] = 16'h0787; // ADD R7, R0, 7   warm-up
        dut.imem_inst.mem[1] = 16'h0787; // ADD R7, R0, 7   warm-up
        dut.imem_inst.mem[2] = 16'h0787; // ADD R7, R0, 7   warm-up
        dut.imem_inst.mem[3] = 16'h0481; // ADD R1, R0, 1
        dut.imem_inst.mem[4] = 16'h0110; // ADD R2, R1, R0
        dut.imem_inst.mem[5] = 16'h0583; // ADD R3, R0, 3
        dut.imem_inst.mem[6] = 16'h0604; // ADD R4, R0, 4
        dut.imem_inst.mem[7] = 16'h0685; // ADD R5, R0, 5
        dut.imem_inst.mem[8] = 16'h0340; // ADD R6, R4, R0
        dut.imem_inst.mem[9] = 16'h4380; // HALT
        for (i = 10; i < 28; i = i + 1)
            dut.imem_inst.mem[i] = 16'h4380; // padding
    end

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Golden per-cycle trace, captured from a known-correct Stage-C
    // reference (built from your draft after the three fixes) and
    // hand-checked at the key cycles: gap=0 now costs zero stall cycles
    // (cyc 7->8->9 advance back-to-back with no freeze), with fwd_mem_a
    // firing at cyc 9 to supply P1's result into C1's ALU input while
    // C1 is in Compute and P1 is in Memory. The gap=1 case still stalls
    // for 2 cycles (cyc 12-13), unchanged from Stage B.
    reg [47:0] expected       [0:20];
    reg        expected_stall [0:20];
    reg        expected_fwd_a [0:20];
    reg        expected_fwd_b [0:20];

    initial begin
        expected[0]  = 48'h000000000000; expected_stall[0]  = 1'b0; expected_fwd_a[0]  = 1'b0; expected_fwd_b[0]  = 1'b0;
        expected[1]  = 48'h000107870000; expected_stall[1]  = 1'b0; expected_fwd_a[1]  = 1'b0; expected_fwd_b[1]  = 1'b0;
        expected[2]  = 48'h000207870000; expected_stall[2]  = 1'b1; expected_fwd_a[2]  = 1'b1; expected_fwd_b[2]  = 1'b0; // residual phantom, harmless
        expected[3]  = 48'h000207870007; expected_stall[3]  = 1'b1; expected_fwd_a[3]  = 1'b0; expected_fwd_b[3]  = 1'b0;
        expected[4]  = 48'h000207870000; expected_stall[4]  = 1'b1; expected_fwd_a[4]  = 1'b0; expected_fwd_b[4]  = 1'b0;
        expected[5]  = 48'h000207870000; expected_stall[5]  = 1'b0; expected_fwd_a[5]  = 1'b0; expected_fwd_b[5]  = 1'b0;
        expected[6]  = 48'h000307870000; expected_stall[6]  = 1'b0; expected_fwd_a[6]  = 1'b0; expected_fwd_b[6]  = 1'b0;
        expected[7]  = 48'h000404810007; expected_stall[7]  = 1'b0; expected_fwd_a[7]  = 1'b0; expected_fwd_b[7]  = 1'b0;
        expected[8]  = 48'h000501100007; expected_stall[8]  = 1'b0; expected_fwd_a[8]  = 1'b0; expected_fwd_b[8]  = 1'b0; // C1 in Decode, NO stall
        expected[9]  = 48'h000605830001; expected_stall[9]  = 1'b0; expected_fwd_a[9]  = 1'b1; expected_fwd_b[9]  = 1'b0; // C1 in Compute, P1 in Memory: forwarded!
        expected[10] = 48'h000706040001; expected_stall[10] = 1'b0; expected_fwd_a[10] = 1'b0; expected_fwd_b[10] = 1'b0;
        expected[11] = 48'h000806850003; expected_stall[11] = 1'b0; expected_fwd_a[11] = 1'b0; expected_fwd_b[11] = 1'b0;
        expected[12] = 48'h000903400004; expected_stall[12] = 1'b1; expected_fwd_a[12] = 1'b0; expected_fwd_b[12] = 1'b0; // gap=1 still stalls
        expected[13] = 48'h000903400005; expected_stall[13] = 1'b1; expected_fwd_a[13] = 1'b0; expected_fwd_b[13] = 1'b0;
        expected[14] = 48'h000903400000; expected_stall[14] = 1'b0; expected_fwd_a[14] = 1'b0; expected_fwd_b[14] = 1'b0;
        expected[15] = 48'h000a43800000; expected_stall[15] = 1'b0; expected_fwd_a[15] = 1'b0; expected_fwd_b[15] = 1'b0;
        expected[16] = 48'h000b43800004; expected_stall[16] = 1'b0; expected_fwd_a[16] = 1'b0; expected_fwd_b[16] = 1'b0;
        expected[17] = 48'h000c43800000; expected_stall[17] = 1'b0; expected_fwd_a[17] = 1'b0; expected_fwd_b[17] = 1'b0;
        expected[18] = 48'h000d43800000; expected_stall[18] = 1'b0; expected_fwd_a[18] = 1'b0; expected_fwd_b[18] = 1'b0;
        expected[19] = 48'h000e43800000; expected_stall[19] = 1'b0; expected_fwd_a[19] = 1'b0; expected_fwd_b[19] = 1'b0;
        expected[20] = 48'h000f43800000; expected_stall[20] = 1'b0; expected_fwd_a[20] = 1'b0; expected_fwd_b[20] = 1'b0;
    end

    reg [15:0] expected_regs [0:7];
    initial begin
        expected_regs[0] = 16'h0000;
        expected_regs[1] = 16'h0001;
        expected_regs[2] = 16'h0001; // R2 = R1, resolved with zero stall via forwarding
        expected_regs[3] = 16'h0003;
        expected_regs[4] = 16'h0004;
        expected_regs[5] = 16'h0005;
        expected_regs[6] = 16'h0004; // R6 = R4, still via a 2-cycle stall (gap=1)
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
            if (dut.fwd_mem_a !== expected_fwd_a[cyc]) begin
                errors = errors + 1;
                $display("FAIL cyc %0d: got fwd_mem_a=%b expected %b", cyc, dut.fwd_mem_a, expected_fwd_a[cyc]);
            end
            if (dut.fwd_mem_b !== expected_fwd_b[cyc]) begin
                errors = errors + 1;
                $display("FAIL cyc %0d: got fwd_mem_b=%b expected %b", cyc, dut.fwd_mem_b, expected_fwd_b[cyc]);
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
            $display("ALL CHECKS PASSED -- tb_cpu_stageC looks correct (per-cycle cpu_out/stall/forwarding trace, final register file)");
        else
            $display("%0d ERROR(S) FOUND", errors);

        $finish;
    end

endmodule