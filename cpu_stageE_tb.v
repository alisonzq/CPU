`timescale 1ns / 1ps
//
// Testbench for the Stage-E Part 2 pipelined cpu.v: the hardware-based
// branch-penalty optimization. Target address and the register comparison
// both move into Decode (a dedicated subtract-based comparator feeding a
// second condition_encoding instance), so is_branch_taken/target are now
// fully combinational Decode-stage signals instead of latched _ex-stage
// ones. This cuts the taken-branch penalty from 2 wrong-path instructions
// down to 1, at the cost of losing Compute-stage forwarding into a
// branch's own comparison operands -- a branch depending on a very recent
// producer must now stall instead of forwarding.
//
// Checks cpu_out, stall, is_branch_taken, and target every cycle against a
// precomputed golden trace, plus the final register file.
//
// Test program (same shape as the Part-1 testbench, but the *timing* is
// now different since Part 2 stalls in different places and only ever
// squashes exactly one wrong-path instruction):
//
//   mem[0..2]  = 0x0787   ADD R7, R0, 7 (x3)     warm-up (drain reset phantom)
//   mem[3]     = 0x4100   BEQ +2, R0, R0         taken (R0==R0)
//   mem[4]     = 0x0481   ADD R1, R0, 1          wrong-path, MUST be squashed
//   mem[5]     = 0x0502   ADD R2, R0, 2          NEVER FETCHED -- Part 2 only
//                          discards 1 wrong-path instruction, not 2; PC
//                          redirects to the target before this word is
//                          ever read
//   mem[6]     = 0x0583   ADD R3, R0, 3          target, must execute
//   mem[7]     = 0x40F0   BEQ +1, R7, R0         NOT taken (7 != 0) -- zero
//                          penalty, sequential flow must continue untouched
//   mem[8]     = 0x0604   ADD R4, R0, 4          normal flow after a
//                          not-taken branch (no bubble should appear here)
//   mem[9]     = 0x0707   ADD R6, R0, 7          producer, gap=0 into the
//                          branch below -- Decode has NO forwarding, so
//                          this now costs the branch 2 stall cycles
//                          (producer in Execute, then in Memory) before it
//                          can safely re-read R6 from the register file
//   mem[10]    = 0x4167   BEQ +2, R6, R7         taken (R6 == R7 once the
//                          stalls clear); if either new stall term were
//                          missing this would wrongly resolve not-taken
//   mem[11]    = 0x0685   ADD R5, R0, 5          wrong-path, MUST be squashed
//   mem[12]    = 0x0602   ADD R4, R0, 2          NEVER FETCHED (same reason
//                          as mem[5] -- would corrupt R4 if it ever ran)
//   mem[13]    = 0x0686   ADD R5, R0, 6          target, must execute
//   mem[14]    = 0x4380   HALT, padded
//
// Run with, e.g.:
//   iverilog -o cpu_tb.vvp alu.v registerfile.v ins_mem.v data_mem.v condition_encoding.v cpu.v tb_cpu_stageE2.v
//   vvp cpu_tb.vvp
//
module cpu_stageE_tb;

    reg clk;
    reg reset;
    wire [47:0] cpu_out;
    wire        halt;
    integer i;

    localparam NUM_CYCLES = 30;

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
        dut.imem_inst.mem[3]  = 16'h4100; // BEQ +2, R0, R0   -- taken
        dut.imem_inst.mem[4]  = 16'h0481; // ADD R1, R0, 1    -- wrong-path
        dut.imem_inst.mem[5]  = 16'h0502; // ADD R2, R0, 2    -- never fetched
        dut.imem_inst.mem[6]  = 16'h0583; // ADD R3, R0, 3    -- target
        dut.imem_inst.mem[7]  = 16'h40F0; // BEQ +1, R7, R0   -- NOT taken
        dut.imem_inst.mem[8]  = 16'h0604; // ADD R4, R0, 4    -- normal flow
        dut.imem_inst.mem[9]  = 16'h0707; // ADD R6, R0, 7    -- producer (gap=0 into branch)
        dut.imem_inst.mem[10] = 16'h4167; // BEQ +2, R6, R7   -- taken, needs the new stall terms
        dut.imem_inst.mem[11] = 16'h0685; // ADD R5, R0, 5    -- wrong-path
        dut.imem_inst.mem[12] = 16'h0602; // ADD R4, R0, 2    -- never fetched
        dut.imem_inst.mem[13] = 16'h0686; // ADD R5, R0, 6    -- target
        dut.imem_inst.mem[14] = 16'h4380; // HALT
        for (i = 15; i < 32; i = i + 1)
            dut.imem_inst.mem[i] = 16'h4380; // padding (also self-taken branches)
    end

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Golden per-cycle trace, captured from a Stage-E-Part-2 reference built
    // by: (1) adding a Decode-stage subtractor/comparator so is_branch_taken
    // and target are fully combinational off live IR/regfile_A/regfile_B,
    // (2) reverting the _ex latch's bubble condition to "stall" alone (no
    // wrong-path instruction rides into _ex anymore -- only one fetch ever
    // needs discarding, and that happens in the PC/IR block), and (3) two
    // NEW stall terms specific to branches, since Decode has no forwarding
    // network at all: "is_branch && writes_back_ex && ..." (producer still
    // in Execute, gap=0) and "is_branch && writes_back_mem && ..." (producer
    // has moved to Memory, gap=1) -- both needed, since a branch can't use
    // fwd_mem_a/fwd_wb_a the way an ordinary ALU consumer would.
    reg [47:0] expected      [0:30];
    reg        expected_stall[0:30];
    reg        expected_taken[0:30];
    reg [15:0] expected_target[0:30];

    task set_row;
        input integer idx;
        input [47:0] cpu_out_val;
        input        stall_val, taken_val;
        input [15:0] target_val;
        begin
            expected[idx]        = cpu_out_val;
            expected_stall[idx]  = stall_val;
            expected_taken[idx]  = taken_val;
            expected_target[idx] = target_val;
        end
    endtask

    initial begin
        set_row( 0, 48'h000000000000, 0, 0, 16'h0000);
        set_row( 1, 48'h000107870000, 0, 0, 16'h0000);
        set_row( 2, 48'h000207870000, 0, 0, 16'h0001);
        set_row( 3, 48'h000307870007, 1, 0, 16'h0002);
        set_row( 4, 48'h000307870007, 1, 0, 16'h0002);
        set_row( 5, 48'h000307870000, 1, 0, 16'h0002);
        set_row( 6, 48'h000307870000, 0, 0, 16'h0002);
        set_row( 7, 48'h000441000007, 0, 1, 16'h0006); // BEQ +2,R0,R0 resolves taken IN DECODE
        set_row( 8, 48'h000600000007, 0, 0, 16'h0006); // wrong-path (mem[4]) squashed via IR bubble
        set_row( 9, 48'h000705830000, 0, 0, 16'h000a); // target ADD R3,R0,3 fetched directly -- mem[5] skipped entirely
        set_row(10, 48'h000840f00000, 1, 0, 16'h0009); // R3=3 lands in RZ
        set_row(11, 48'h000840f00003, 1, 0, 16'h0009);
        set_row(12, 48'h000840f00000, 0, 0, 16'h0009);
        set_row(13, 48'h000906040007, 0, 0, 16'h0005); // BEQ +1,R7,R0 resolves NOT taken
        set_row(14, 48'h000a07070007, 0, 0, 16'h0008); // normal flow continues, zero penalty
        set_row(15, 48'h000b41670004, 1, 0, 16'h000d); // BEQ +2,R6,R7 in decode; producer still in _ex -- stall
        set_row(16, 48'h000b41670007, 1, 0, 16'h000d); // producer now in _mem -- still stall (no fwd into decode)
        set_row(17, 48'h000b41670007, 1, 0, 16'h000d);
        set_row(18, 48'h000b41670007, 0, 1, 16'h000d); // producer safely in regfile -- resolves taken
        set_row(19, 48'h000d00000007, 0, 0, 16'h000d); // wrong-path (mem[11]) squashed
        set_row(20, 48'h000e06860000, 0, 0, 16'h000b); // target ADD R5,R0,6 fetched directly -- mem[12] skipped
        set_row(21, 48'h000f43800000, 1, 1, 16'h000e); // R5=6 lands in RZ; halt's self-branch taken
        set_row(22, 48'h000e00000006, 1, 0, 16'h000e);
        set_row(23, 48'h000e00000000, 0, 0, 16'h000e);
        set_row(24, 48'h000f43800000, 1, 1, 16'h000e);
        set_row(25, 48'h000e00000000, 0, 0, 16'h000e);
        set_row(26, 48'h000f43800000, 1, 1, 16'h000e);
        set_row(27, 48'h000e00000000, 0, 0, 16'h000e);
        set_row(28, 48'h000f43800000, 1, 1, 16'h000e);
        set_row(29, 48'h000e00000000, 0, 0, 16'h000e);
        set_row(30, 48'h000f43800000, 1, 1, 16'h000e);
    end

    reg [15:0] expected_regs [0:7];
    initial begin
        expected_regs[0] = 16'h0000;
        expected_regs[1] = 16'h0000; // squashed wrong-path write, must never land
        expected_regs[2] = 16'h0000; // mem[5] never even fetched
        expected_regs[3] = 16'h0003; // first branch's target
        expected_regs[4] = 16'h0004; // set by normal (not-taken) flow; mem[12] never fetched to corrupt it
        expected_regs[5] = 16'h0006; // second branch's target
        expected_regs[6] = 16'h0007; // producer, correctly available after the 2-cycle stall chain
        expected_regs[7] = 16'h0007; // untouched since warm-up
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
            if (dut.is_branch_taken !== expected_taken[cyc]) begin
                errors = errors + 1;
                $display("FAIL cyc %0d: got is_branch_taken=%b expected %b", cyc, dut.is_branch_taken, expected_taken[cyc]);
            end
            if (dut.target !== expected_target[cyc]) begin
                errors = errors + 1;
                $display("FAIL cyc %0d: got target=%h expected %h", cyc, dut.target, expected_target[cyc]);
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
            $display("ALL CHECKS PASSED -- tb_cpu_stageE2 looks correct (per-cycle cpu_out/stall/is_branch_taken/target trace, final register file)");
        else
            $display("%0d ERROR(S) FOUND", errors);

        $finish;
    end

endmodule