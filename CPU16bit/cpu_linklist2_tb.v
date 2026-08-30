`timescale 1ns / 1ps
//
// Testbench for cpu.v (Task 4) -- replays linklisttest2.rom and checks the
// resulting cpu_out {PC,IR,RZ} against the real golden trace in
// linklisttest2.out.
//
// linklisttest2.out is a CHANGE LOG just like Task 3's aluinstrtest.out: a new
// row appears only when cpu_out actually changes (Fetch changes PC/IR;
// Execute changes RZ). Decode/Memory/Writeback never touch cpu_out, so
// they never produce a new row -- this matters a lot here since Task 4
// adds Load/Store, which spend a Memory cycle that produces no new row.
//
// This program is straight-line code (no branches taken before the
// final halt instruction), so every one of the 42 instructions in
// linklisttest2.rom is fetched and executed exactly once, for 70
// total distinct cpu_out values (matching the 70 rows of
// linklisttest2.out) before the halt instruction (0x4380, BEQ -1,R0,R0) is
// fetched.
//
// Run with, e.g.:
//   iverilog -o cpu_tb.vvp alu.v registerfile.v control_fsm.v ins_mem.v data_mem.v cpu.v tb_cpu_linklist2.v
//   vvp cpu_tb.vvp
// (adjust file names to whatever you actually called your modules)
//
module cpu_linklist2_tb;

    reg clk;
    reg reset;
    wire [47:0] cpu_out;
    wire        halt;

    localparam MAX_CYCLES = 2000; // safety timeout in case the CPU gets stuck

    // NOTE: change "cpu" here if you rename/re-case your top module.
    // MEM_FILE left at its default ("") -- we load the instruction ROM
    // directly below instead of via $readmemh, same as Task 3.
    cpu dut (
        .clk(clk),
        .reset(reset),
        .cpu_out(cpu_out),
        .halt(halt)
    );

    // Load linklisttest2.rom's contents directly into ins_mem's array via a
    // hierarchical reference, instead of $readmemh from a file.
    // Adjust the path below if your instance/array names differ from
    // imem_inst / mem.
    initial begin
        dut.imem_inst.mem[0] = 16'h0490;
        dut.imem_inst.mem[1] = 16'h0522;
        dut.imem_inst.mem[2] = 16'h05b4;
        dut.imem_inst.mem[3] = 16'hc4a0;
        dut.imem_inst.mem[4] = 16'hc5a0;
        dut.imem_inst.mem[5] = 16'h0f21;
        dut.imem_inst.mem[6] = 16'h07f3;
        dut.imem_inst.mem[7] = 16'hc4e0;
        dut.imem_inst.mem[8] = 16'hc7e0;
        dut.imem_inst.mem[9] = 16'h0646;
        dut.imem_inst.mem[10] = 16'hc4b0;
        dut.imem_inst.mem[11] = 16'hc630;
        dut.imem_inst.mem[12] = 16'h0f31;
        dut.imem_inst.mem[13] = 16'hc4e0;
        dut.imem_inst.mem[14] = 16'hc7e0;
        dut.imem_inst.mem[15] = 16'h06d7;
        dut.imem_inst.mem[16] = 16'h06d1;
        dut.imem_inst.mem[17] = 16'hc4c0;
        dut.imem_inst.mem[18] = 16'hc6c0;
        dut.imem_inst.mem[19] = 16'h0f41;
        dut.imem_inst.mem[20] = 16'hc4e0;
        dut.imem_inst.mem[21] = 16'hc7e0;
        dut.imem_inst.mem[22] = 16'h8720;
        dut.imem_inst.mem[23] = 16'h0760;
        dut.imem_inst.mem[24] = 16'h0ca1;
        dut.imem_inst.mem[25] = 16'h8510;
        dut.imem_inst.mem[26] = 16'h0520;
        dut.imem_inst.mem[27] = 16'h1400;
        dut.imem_inst.mem[28] = 16'h0002;
        dut.imem_inst.mem[29] = 16'h87e0;
        dut.imem_inst.mem[30] = 16'h07f0;
        dut.imem_inst.mem[31] = 16'h0ce1;
        dut.imem_inst.mem[32] = 16'h8510;
        dut.imem_inst.mem[33] = 16'h0520;
        dut.imem_inst.mem[34] = 16'h0002;
        dut.imem_inst.mem[35] = 16'h85f0;
        dut.imem_inst.mem[36] = 16'h05b0;
        dut.imem_inst.mem[37] = 16'h0cf1;
        dut.imem_inst.mem[38] = 16'h8510;
        dut.imem_inst.mem[39] = 16'h0520;
        dut.imem_inst.mem[40] = 16'h0002;
        dut.imem_inst.mem[41] = 16'h4380;
    end

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // The 70-row golden trace from linklisttest2.out, each row packed as
    // {PC[15:0], IR[15:0], RZ[15:0]}.
    reg [47:0] expected [0:69];

    initial begin
        expected[0] = 48'h000000000000;
        expected[1] = 48'h000104900000;
        expected[2] = 48'h000205220000;
        expected[3] = 48'h000205220002;
        expected[4] = 48'h000305b40002;
        expected[5] = 48'h000305b40004;
        expected[6] = 48'h0004c4a00004;
        expected[7] = 48'h0004c4a00002;
        expected[8] = 48'h0005c5a00002;
        expected[9] = 48'h00060f210002;
        expected[10] = 48'h00060f210001;
        expected[11] = 48'h000707f30001;
        expected[12] = 48'h000707f30003;
        expected[13] = 48'h0008c4e00003;
        expected[14] = 48'h0008c4e00001;
        expected[15] = 48'h0009c7e00001;
        expected[16] = 48'h000a06460001;
        expected[17] = 48'h000a06460006;
        expected[18] = 48'h000bc4b00006;
        expected[19] = 48'h000bc4b00004;
        expected[20] = 48'h000cc6300004;
        expected[21] = 48'h000d0f310004;
        expected[22] = 48'h000d0f310003;
        expected[23] = 48'h000ec4e00003;
        expected[24] = 48'h000fc7e00003;
        expected[25] = 48'h001006d70003;
        expected[26] = 48'h001006d70007;
        expected[27] = 48'h001106d10007;
        expected[28] = 48'h001106d10008;
        expected[29] = 48'h0012c4c00008;
        expected[30] = 48'h0012c4c00006;
        expected[31] = 48'h0013c6c00006;
        expected[32] = 48'h00140f410006;
        expected[33] = 48'h00140f410005;
        expected[34] = 48'h0015c4e00005;
        expected[35] = 48'h0016c7e00005;
        expected[36] = 48'h001787200005;
        expected[37] = 48'h001787200002;
        expected[38] = 48'h001807600002;
        expected[39] = 48'h001807600004;
        expected[40] = 48'h00190ca10004;
        expected[41] = 48'h00190ca10001;
        expected[42] = 48'h001a85100001;
        expected[43] = 48'h001b05200001;
        expected[44] = 48'h001b05200003;
        expected[45] = 48'h001c14000003;
        expected[46] = 48'h001c14000000;
        expected[47] = 48'h001d00020000;
        expected[48] = 48'h001d00020003;
        expected[49] = 48'h001e87e00003;
        expected[50] = 48'h001e87e00004;
        expected[51] = 48'h001f07f00004;
        expected[52] = 48'h001f07f00006;
        expected[53] = 48'h00200ce10006;
        expected[54] = 48'h00200ce10003;
        expected[55] = 48'h002185100003;
        expected[56] = 48'h002205200003;
        expected[57] = 48'h002300020003;
        expected[58] = 48'h002300020006;
        expected[59] = 48'h002485f00006;
        expected[60] = 48'h002505b00006;
        expected[61] = 48'h002505b00008;
        expected[62] = 48'h00260cf10008;
        expected[63] = 48'h00260cf10005;
        expected[64] = 48'h002785100005;
        expected[65] = 48'h002805200005;
        expected[66] = 48'h002805200003;
        expected[67] = 48'h002900020003;
        expected[68] = 48'h002900020009;
        expected[69] = 48'h002a43800009;
    end

    reg [47:0] prev_cpu_out;
    integer    idx;
    integer    errors;
    integer    cycle_count;

    initial begin
        reset = 1'b1;
        @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        idx = 0;
        errors = 0;
        cycle_count = 0;

        // check the post-reset state itself against expected[0]
        if (cpu_out !== expected[0]) begin
            errors = errors + 1;
            $display("FAIL sample %0d: got %h expected %h (post-reset state)", idx, cpu_out, expected[0]);
        end
        prev_cpu_out = cpu_out;
        idx = idx + 1;

        while (!halt && cycle_count < MAX_CYCLES) begin
            @(posedge clk);
            #1; // let combinational logic (halt, cpu_out) settle
            cycle_count = cycle_count + 1;

            if (cpu_out !== prev_cpu_out) begin
                if (idx > 69) begin
                    errors = errors + 1;
                    $display("FAIL: unexpected extra cpu_out change at cycle %0d: got %h (only 70 changes expected)",
                              cycle_count, cpu_out);
                end else begin
                    if (cpu_out !== expected[idx]) begin
                        errors = errors + 1;
                        $display("FAIL sample %0d (cycle %0d): got %h expected %h",
                                  idx, cycle_count, cpu_out, expected[idx]);
                    end
                    idx = idx + 1;
                end
                prev_cpu_out = cpu_out;
            end
        end

        if (cycle_count >= MAX_CYCLES) begin
            errors = errors + 1;
            $display("FAIL: halt never went high within %0d cycles -- CPU is likely stuck", MAX_CYCLES);
        end

        if (idx != 70) begin
            errors = errors + 1;
            $display("FAIL: expected 70 distinct cpu_out values before halt, observed %0d", idx);
        end

        if (errors == 0)
            $display("ALL %0d EXPECTED CPU_OUT TRANSITIONS MATCHED -- tb_cpu_linklist2 looks correct", idx);
        else
            $display("%0d ERROR(S) FOUND", errors);

        $finish;
    end

endmodule