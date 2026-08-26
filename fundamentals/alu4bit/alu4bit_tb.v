`timescale 1ns/1ps

module alu4bit_tb;

    reg  [3:0] a, b;
    reg  [2:0] op;
    wire [3:0] result;
    wire zero, carry;
    integer errors = 0;

    alu4bit dut (
        .a(a), .b(b), .op(op),
        .result(result), .zero(zero), .carry(carry)
    );

    initial begin
        $dumpfile("alu4bit.vcd");
        $dumpvars(0, alu4bit_tb);
    end

    task check(input [3:0] a_in, input [3:0] b_in, input [2:0] op_in,
               input [3:0] exp_result, input exp_zero);
        begin
            a = a_in; b = b_in; op = op_in;
            #10;
            if (result !== exp_result || zero !== exp_zero) begin
                $display("FAIL: a=%d b=%d op=%b -> result=%d zero=%b (expected result=%d zero=%b)",
                          a, b, op, result, zero, exp_result, exp_zero);
                errors = errors + 1;
            end else begin
                $display("PASS: a=%d b=%d op=%b -> result=%d zero=%b carry=%b", a, b, op, result, zero, carry);
            end
        end
    endtask

    initial begin
        // ADD
        check(4'd3, 4'd4, 3'b000, 4'd7, 0);
        check(4'd15, 4'd1, 3'b000, 4'd0, 1); // overflow wraps, carry should be set
        // SUB
        check(4'd5, 4'd3, 3'b001, 4'd2, 0);
        check(4'd3, 4'd3, 3'b001, 4'd0, 1);
        // AND / OR / XOR
        check(4'b1100, 4'b1010, 3'b010, 4'b1000, 0);
        check(4'b1100, 4'b1010, 3'b011, 4'b1110, 0);
        check(4'b1100, 4'b1010, 3'b100, 4'b0110, 0);
        // SLT
        check(4'd2, 4'd5, 3'b101, 4'd1, 0);
        check(4'd5, 4'd2, 3'b101, 4'd0, 1);

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TEST(S) FAILED", errors);

        $finish;
    end

endmodule
