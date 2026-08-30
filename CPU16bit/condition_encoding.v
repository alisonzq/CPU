module condition_encoding(
	input wire Z,
	input wire N,
	input wire V,
	input wire [2:0] condition,
	output wire C
);
	
	localparam EQ = 3'b000;
	localparam NE = 3'b001;
	localparam LT = 3'b010;
	localparam LE = 3'b011;
	localparam GT = 3'b100;
	localparam GE = 3'b101;
	
	always @(*) begin
		case(condition)
			EQ: C = Z == 1'b1;
			NE: C = Z == 1'b0;
			LT: C = N != V;
			LE: C = (Z == 1'b1) || (N != V);
			GT: C = (Z == 1'b0) && (N == V);
			GE: C = N == V;
			default: C = 1'b0;
		endcase
	end
endmodule

	