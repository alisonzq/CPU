`timescale 1ns / 1ps
//
// Testbench for the ALU module (Task 1), using the exact 28 test
// vectors below (fun, A, B, C, N, Z, carry, overflow).
//
// For AND/OR/NOR/shift rows, carry and overflow are "don't care" per
// the ALU spec, so those rows are checked with check_cnz (C/N/Z only).
// ADD/SUB rows define all four flags, so those use check_full.
//
module alu_tb;

    reg  [15:0] A, B;
    reg  [2:0]  fun;
    wire [15:0] C;
    wire        negative, zero, carry, overflow;

    integer tests  = 0;
    integer errors = 0;

    // NOTE: change "alu" here if you rename/re-case your module.
    alu dut (
        .A(A), .B(B), .fun(fun),
        .C(C), .negative(negative), .zero(zero),
        .carry(carry), .overflow(overflow)
    );

    localparam OP_ADD = 3'b000;
    localparam OP_SUB = 3'b001;
    localparam OP_AND = 3'b010;
    localparam OP_OR  = 3'b011;
    localparam OP_NOR = 3'b100;
    localparam OP_LSL = 3'b101;
    localparam OP_LSR = 3'b110;
    localparam OP_ASR = 3'b111;

    // Full check: verifies C, N, Z, carry AND overflow. Use for ADD/SUB.
    task check_full(
        input [15:0] a, input [15:0] b, input [2:0] f,
        input [15:0] exp_c, input exp_n, input exp_z,
        input exp_cy, input exp_v
    );
        begin
            A = a; B = b; fun = f;
            #1;
            tests = tests + 1;
            if (C !== exp_c || negative !== exp_n || zero !== exp_z ||
                carry !== exp_cy || overflow !== exp_v) begin
                errors = errors + 1;
                $display("FAIL fun=%b A=%h B=%h | got  C=%h N=%b Z=%b Cy=%b V=%b | exp  C=%h N=%b Z=%b Cy=%b V=%b",
                          f, a, b, C, negative, zero, carry, overflow,
                          exp_c, exp_n, exp_z, exp_cy, exp_v);
            end
        end
    endtask

    // Partial check: C/N/Z only. carry/overflow are "x" (don't care) in
    // the vector table for AND/OR/NOR/shifts, so we don't compare them.
    task check_cnz(
        input [15:0] a, input [15:0] b, input [2:0] f,
        input [15:0] exp_c, input exp_n, input exp_z
    );
        begin
            A = a; B = b; fun = f;
            #1;
            tests = tests + 1;
            if (C !== exp_c || negative !== exp_n || zero !== exp_z) begin
                errors = errors + 1;
                $display("FAIL fun=%b A=%h B=%h | got  C=%h N=%b Z=%b | exp  C=%h N=%b Z=%b",
                          f, a, b, C, negative, zero, exp_c, exp_n, exp_z);
            end
        end
    endtask

    initial begin
        // ---- ADD (000) ----
        check_full(16'h0003, 16'h0007, OP_ADD, 16'h000A, 1'b0, 1'b0, 1'b0, 1'b0); // add 3, 7 = 10
        check_full(16'hFFF9, 16'hFFFD, OP_ADD, 16'hFFF6, 1'b1, 1'b0, 1'b1, 1'b0); // add -7, -3 = -10
        check_full(16'hFFF9, 16'h0003, OP_ADD, 16'hFFFC, 1'b1, 1'b0, 1'b0, 1'b0); // add -7,  3 = -4
        check_full(16'hFFFD, 16'h0007, OP_ADD, 16'h0004, 1'b0, 1'b0, 1'b1, 1'b0); // add -3,  7 =  4
        check_full(16'hFFFD, 16'h0003, OP_ADD, 16'h0000, 1'b0, 1'b1, 1'b1, 1'b0); // add -3,  3 =  0
        check_full(16'h7FFF, 16'h0001, OP_ADD, 16'h8000, 1'b1, 1'b0, 1'b0, 1'b1); // add (2^15-1), 1 -> overflow
        check_full(16'h8000, 16'h8001, OP_ADD, 16'h0001, 1'b0, 1'b0, 1'b1, 1'b1); // add -2^15, (-2^15+1) = 1 -> overflow

        // ---- SUB (001) ----
        check_full(16'h0003, 16'h0007, OP_SUB, 16'hFFFC, 1'b1, 1'b0, 1'b0, 1'b0); // sub 3, 7 = -4
        check_full(16'h0007, 16'h0003, OP_SUB, 16'h0004, 1'b0, 1'b0, 1'b1, 1'b0); // sub 7, 3 = 4
        check_full(16'hFFFD, 16'hFFF9, OP_SUB, 16'h0004, 1'b0, 1'b0, 1'b1, 1'b0); // sub -3, -7 = 4
        check_full(16'hFFF9, 16'h0003, OP_SUB, 16'hFFF6, 1'b1, 1'b0, 1'b1, 1'b0); // sub -7, 3 = -10
        check_full(16'h0007, 16'h0007, OP_SUB, 16'h0000, 1'b0, 1'b1, 1'b1, 1'b0); // sub 7, 7 = 0
        check_full(16'h7FFF, 16'hFFFF, OP_SUB, 16'h8000, 1'b1, 1'b0, 1'b0, 1'b1); // sub (2^15-1), -1 = -2^15 -> overflow
        check_full(16'h8000, 16'h0001, OP_SUB, 16'h7FFF, 1'b0, 1'b0, 1'b1, 1'b1); // sub -2^15, 1 = (2^15-1) -> overflow

        // ---- AND (010) ----
        check_cnz(16'h0001, 16'h0003, OP_AND, 16'h0001, 1'b0, 1'b0); // and overlap
        check_cnz(16'h8000, 16'h7FFF, OP_AND, 16'h0000, 1'b0, 1'b1); // and no overlap
        check_cnz(16'hFFFF, 16'hFFFF, OP_AND, 16'hFFFF, 1'b1, 1'b0); // and fully overlap

        // ---- OR (011) ----
        check_cnz(16'h0001, 16'h0003, OP_OR,  16'h0003, 1'b0, 1'b0); // or overlap
        check_cnz(16'h8000, 16'h7FFF, OP_OR,  16'hFFFF, 1'b1, 1'b0); // or no overlap
        check_cnz(16'h0001, 16'h0001, OP_OR,  16'h0001, 1'b0, 1'b0); // or fully overlap

        // ---- NOR (100) ----
        check_cnz(16'h0001, 16'h0003, OP_NOR, 16'hFFFC, 1'b1, 1'b0); // nor overlap
        check_cnz(16'h8000, 16'h7FFF, OP_NOR, 16'h0000, 1'b0, 1'b1); // nor no overlap
        check_cnz(16'h0001, 16'h0001, OP_NOR, 16'hFFFE, 1'b1, 1'b0); // nor fully overlap

        // ---- LSL (101) ----
        check_cnz(16'h8008, 16'h0003, OP_LSL, 16'h0040, 1'b0, 1'b0); // lsl 1000000000001000, 3 = 0000000001000000
        check_cnz(16'h8008, 16'h000C, OP_LSL, 16'h8000, 1'b1, 1'b0); // lsl 1000000000001000, 12 = 1000000000000000

        // ---- LSR (110) ----
        check_cnz(16'h8008, 16'h0003, OP_LSR, 16'h1001, 1'b0, 1'b0); // lsr 1000000000001000, 3 = 0001000000000001

        // ---- ASR (111) ----
        check_cnz(16'h0008, 16'h0003, OP_ASR, 16'h0001, 1'b0, 1'b0); // asr 0000000000001000, 3 = 0000000000000001
        check_cnz(16'h8008, 16'h0003, OP_ASR, 16'hF001, 1'b1, 1'b0); // asr 1000000000001000, 3 = 1111000000000001

        if (errors == 0)
            $display("ALL %0d TESTS PASSED", tests);
        else
            $display("%0d of %0d TESTS FAILED", errors, tests);

        $finish;
    end

endmodule