`timescale 1ns / 1ps
//
// Testbench for cpu.v (Task 5) -- replays mult3.rom and checks the
// resulting cpu_out {PC,IR,RZ} against the real golden trace in
// mult3.out.
//
// Unlike the Task 3/4 tests, this program is NOT straight-line: it's a
// shift-add multiplication routine with backward-taken branches (a real
// loop), so PC in the golden trace does NOT increase monotonically --
// watch for it jumping backward in the middle of the trace, which is
// expected and is exactly what this test is meant to exercise. The
// 26-instruction ROM is fetched/executed a total of 41
// distinct cpu_out values' worth of times (i.e. more than 26
// Fetches happen overall, because of the loop).
//
// mult3.out is a CHANGE LOG just like every previous task's .out file:
// a new row appears only when cpu_out actually changes.
//
module cpu_mult3_tb;

    reg clk;
    reg reset;
    wire [47:0] cpu_out;
    wire        halt;

    localparam MAX_CYCLES = 3000; // safety timeout in case the CPU gets stuck (loop makes this longer than Task 4)

    // NOTE: change "cpu" here if you rename/re-case your top module.
    // MEM_FILE left at its default ("") -- we load the instruction ROM
    // directly below instead of via $readmemh, same as previous tasks.
    cpu dut (
        .clk(clk),
        .reset(reset),
        .cpu_out(cpu_out),
        .halt(halt)
    );

    // Load mult3.rom's contents directly into ins_mem's array via a
    // hierarchical reference, instead of $readmemh from a file.
    // Adjust the path below if your instance/array names differ from
    // imem_inst / mem.
    initial begin
        dut.imem_inst.mem[0] = 16'h049e;
        dut.imem_inst.mem[1] = 16'h6d90;
        dut.imem_inst.mem[2] = 16'h2091;
        dut.imem_inst.mem[3] = 16'h0491;
        dut.imem_inst.mem[4] = 16'h0401;
        dut.imem_inst.mem[5] = 16'h052f;
        dut.imem_inst.mem[6] = 16'h6da0;
        dut.imem_inst.mem[7] = 16'h2122;
        dut.imem_inst.mem[8] = 16'h0521;
        dut.imem_inst.mem[9] = 16'h0401;
        dut.imem_inst.mem[10] = 16'h15b0;
        dut.imem_inst.mem[11] = 16'h16d0;
        dut.imem_inst.mem[12] = 16'h1621;
        dut.imem_inst.mem[13] = 16'h4540;
        dut.imem_inst.mem[14] = 16'h4e50;
        dut.imem_inst.mem[15] = 16'h01b1;
        dut.imem_inst.mem[16] = 16'h2c91;
        dut.imem_inst.mem[17] = 16'h4e50;
        dut.imem_inst.mem[18] = 16'h3521;
        dut.imem_inst.mem[19] = 16'h02d2;
        dut.imem_inst.mem[20] = 16'h4e50;
        dut.imem_inst.mem[21] = 16'h4d01;
        dut.imem_inst.mem[22] = 16'h21b3;
        dut.imem_inst.mem[23] = 16'h05b1;
        dut.imem_inst.mem[24] = 16'h05b0;
        dut.imem_inst.mem[25] = 16'h4380;
    end

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // The 41-row golden trace from mult3.out, each row packed as
    // {PC[15:0], IR[15:0], RZ[15:0]}.
    reg [47:0] expected [0:40];

    initial begin
        expected[0] = 48'h000000000000;
        expected[1] = 48'h0001049e0000;
        expected[2] = 48'h0001049efffe;
        expected[3] = 48'h00026d90fffe;
        expected[4] = 48'h00032091fffe;
        expected[5] = 48'h000320910001;
        expected[6] = 48'h000404910001;
        expected[7] = 48'h000404910002;
        expected[8] = 48'h000504010002;
        expected[9] = 48'h000504010001;
        expected[10] = 48'h0006052f0001;
        expected[11] = 48'h0006052fffff;
        expected[12] = 48'h00076da0ffff;
        expected[13] = 48'h00082122ffff;
        expected[14] = 48'h000821220000;
        expected[15] = 48'h000905210000;
        expected[16] = 48'h000905210001;
        expected[17] = 48'h000a04010001;
        expected[18] = 48'h000a04010002;
        expected[19] = 48'h000b15b00002;
        expected[20] = 48'h000b15b00000;
        expected[21] = 48'h000c16d00000;
        expected[22] = 48'h000d16210000;
        expected[23] = 48'h000d16210001;
        expected[24] = 48'h000e45400001;
        expected[25] = 48'h000f4e500001;
        expected[26] = 48'h000f4e500000;
        expected[27] = 48'h001001b10000;
        expected[28] = 48'h001001b10002;
        expected[29] = 48'h00112c910002;
        expected[30] = 48'h00112c910004;
        expected[31] = 48'h00124e500004;
        expected[32] = 48'h00124e500000;
        expected[33] = 48'h001335210000;
        expected[34] = 48'h001402d20000;
        expected[35] = 48'h00154e500000;
        expected[36] = 48'h00164d010000;
        expected[37] = 48'h00184d010001;
        expected[38] = 48'h001905b00001;
        expected[39] = 48'h001905b00002;
        expected[40] = 48'h001a43800002;
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
                if (idx > 40) begin
                    errors = errors + 1;
                    $display("FAIL: unexpected extra cpu_out change at cycle %0d: got %h (only 41 changes expected)",
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

        if (idx != 41) begin
            errors = errors + 1;
            $display("FAIL: expected 41 distinct cpu_out values before halt, observed %0d", idx);
        end

        if (errors == 0)
            $display("ALL %0d EXPECTED CPU_OUT TRANSITIONS MATCHED -- tb_cpu_mult3 looks correct", idx);
        else
            $display("%0d ERROR(S) FOUND", errors);

        $finish;
    end

endmodule