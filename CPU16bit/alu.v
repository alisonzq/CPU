module alu (
	input wire [15:0] A, 
	input wire [15:0] B, 
	input wire [2:0] fun,
	output reg [15:0] C,
	output reg negative,
	output reg zero,
	output reg carry,
	output reg overflow

);
	// Opcodes
	localparam OP_ADD = 3'b000;
	localparam OP_SUB = 3'b001;
	localparam OP_AND = 3'b010;
	localparam OP_OR = 3'b011;
	localparam OP_NOR = 3'b100;
	localparam OP_LSL = 3'b101; 
	localparam OP_LSR = 3'b110;
	localparam OP_ASR = 3'b111;
	
	always @(*) begin
		// defaults, prevents inferred latches if a branch doesn't fully assign
		C   = 16'b0;
		negative = 1'b0;
		zero     = 1'b0;
		carry    = 1'b0;
		overflow = 1'b0;
	 
		case (fun)
			OP_ADD: begin
				{carry, C} = A + B;
				overflow = (A[15] == B[15]) && (C[15] != A[15]);
			end
					
			OP_SUB: begin
				{carry, C} = {1'b0, A} + {1'b0, ~B} + 17'b1;
				overflow = (A[15] != B[15]) && (C[15] != A[15]);
			end
			
			OP_AND: C = A & B;
			OP_OR: C = A | B;
			OP_NOR: C = ~(A | B);
			OP_LSL: C = A << B[3:0];			
			OP_LSR: C = A >> B[3:0];
			OP_ASR: C = $signed(A) >>> B[3:0];

			
			default: C = 16'b0;
		endcase
		
		negative = C[15];
		zero = (C == 16'b0);
	end
	
endmodule
