// 4-bit ALU
// Performs one of several operations on two 4-bit inputs based on a 3-bit opcode.
// This structure (opcode-selected operation) is exactly what you'll build again,
// bigger, inside your RISC-V CPU's execute stage.

module alu4bit (
    input  wire [3:0] a,
    input  wire [3:0] b,
    input  wire [2:0] op,      // operation select
    output reg  [3:0] result,
    output reg        zero,    // flag: result == 0
    output reg        carry    // flag: carry/borrow out of the MSB
);

    // Opcodes
    localparam OP_ADD = 3'b000;
    localparam OP_SUB = 3'b001;
    localparam OP_AND = 3'b010;
    localparam OP_OR  = 3'b011;
    localparam OP_XOR = 3'b100;
    localparam OP_SLT = 3'b101; // set-less-than: result = (a < b) ? 1 : 0

    reg [4:0] temp; // 5 bits wide so we can capture the carry/borrow out

    always @(*) begin
        carry = 1'b0;
        case (op)
            OP_ADD: begin
                temp   = a + b;
                result = temp[3:0];
                carry  = temp[4];
            end
            OP_SUB: begin
                temp   = a - b;
                result = temp[3:0];
                carry  = temp[4]; // borrow flag
            end
            OP_AND: result = a & b;
            OP_OR:  result = a | b;
            OP_XOR: result = a ^ b;
            OP_SLT: result = (a < b) ? 4'b0001 : 4'b0000;
            default: result = 4'b0000;
        endcase

        zero = (result == 4'b0000);
    end

endmodule
