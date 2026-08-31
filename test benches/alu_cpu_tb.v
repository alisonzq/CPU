`timescale 1ns / 1ps
//
// Testbench for cpu.v (Task 3), replaying aluinstrtest.rom and checking
// the resulting cpu_out {PC,IR,RZ} against the real golden trace in
// aluinstrtest.out.
//
// IMPORTANT: aluinstrtest.out is a CHANGE LOG, not a per-cycle dump --
// per the spec, "cpu_out [is shown] as its component signals change
// over the course of execution." A new line only appears when PC/IR
// change (Fetch) or RZ changes (Execute); Decode/Memory/Writeback never
// touch cpu_out, so they never produce a new line. This testbench
// mirrors that: it samples cpu_out every clock and only checks it
// against the next expected row when the value actually changes.
//
// Run with, e.g.:
//   iverilog -o cpu_tb.vvp alu.v registerfile.v control_fsm.v ins_mem.v cpu.v tb_cpu_alu.v
//   vvp cpu_tb.vvp
// (adjust file names to whatever you actually called your modules)
//
module alu_cpu_tb;

    reg clk;
    reg reset;
    wire [47:0] cpu_out;
    wire        halt;

    localparam MAX_CYCLES = 500; // safety timeout in case the CPU gets stuck

    // NOTE: change "cpu" here if you rename/re-case your top module.
    // MEM_FILE left at its default ("") -- we load the ROM directly below
    // instead of via $readmemh, to sidestep the simulator's working-
    // directory issues with finding the file.
    cpu dut (
        .clk(clk),
        .reset(reset),
        .cpu_out(cpu_out),
        .halt(halt)
    );

    // Load aluinstrtest.rom's contents directly into ins_mem's array via a
    // hierarchical reference, instead of $readmemh from a file. This ONLY
    // works in simulation (it reaches straight through the module
    // hierarchy) -- adjust the path below if your instance/array names
    // differ from imem_inst / mem.
    initial begin
        dut.imem_inst.mem[0] = 16'h0400; // ADD R0, R0, 0
        dut.imem_inst.mem[1] = 16'h0e84; // SUB R5, R0, 4
        dut.imem_inst.mem[2] = 16'h1394; // AND R7, R1, R4
        dut.imem_inst.mem[3] = 16'h1e51; // OR  R4, R5, 1
        dut.imem_inst.mem[4] = 16'h2534; // NOR R2, R3, 4
        dut.imem_inst.mem[5] = 16'h2cd4; // LSL R1, R5, 4
        dut.imem_inst.mem[6] = 16'h33d4; // LSR R7, R5, R4
        dut.imem_inst.mem[7] = 16'h3f51; // ASR R6, R5, 1
        dut.imem_inst.mem[8] = 16'h4380; // halt marker (EQ -1, R0, R0)
    end

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // The 17-row golden trace from aluinstrtest.out, each row packed as
    // {PC[15:0], IR[15:0], RZ[15:0]}.
    reg [47:0] expected [0:16];

    initial begin
        expected[0]  = 48'h000000000000; // reset state
        expected[1]  = 48'h000104000000; // fetch ADD R0,R0,0
        expected[2]  = 48'h00020e840000; // fetch SUB R5,R0,4
        expected[3]  = 48'h00020e84fffc; // execute: 0-4 = -4
        expected[4]  = 48'h00031394fffc; // fetch AND R7,R1,R4
        expected[5]  = 48'h000313940000; // execute: R1 & R4 = 0
        expected[6]  = 48'h00041e510000; // fetch OR R4,R5,1
        expected[7]  = 48'h00041e51fffd; // execute: -4 | 1 = -3
        expected[8]  = 48'h00052534fffd; // fetch NOR R2,R3,4
        expected[9]  = 48'h00052534fffb; // execute: ~(R3|4) = -5
        expected[10] = 48'h00062cd4fffb; // fetch LSL R1,R5,4
        expected[11] = 48'h00062cd4ffc0; // execute: -4 << 4 = -64
        expected[12] = 48'h000733d4ffc0; // fetch LSR R7,R5,R4
        expected[13] = 48'h000733d40007; // execute: -4 >>> 4 = 7 (as unsigned shift)
        expected[14] = 48'h00083f510007; // fetch ASR R6,R5,1
        expected[15] = 48'h00083f51fffe; // execute: -4 >>> 1 = -2
        expected[16] = 48'h00094380fffe; // fetch halt instruction (0x4380) -- halt goes high here
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
                if (idx > 16) begin
                    errors = errors + 1;
                    $display("FAIL: unexpected extra cpu_out change at cycle %0d: got %h (only 17 changes expected)",
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

        if (idx != 17) begin
            errors = errors + 1;
            $display("FAIL: expected 17 distinct cpu_out values before halt, observed %0d", idx);
        end

        if (errors == 0)
            $display("ALL %0d EXPECTED CPU_OUT TRANSITIONS MATCHED -- Task 3 looks correct", idx);
        else
            $display("%0d ERROR(S) FOUND", errors);

        $finish;
    end

endmodule