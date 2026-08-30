module control_fsm (
	input wire clk,
	input wire reset,
	output reg ir_we,
	output reg pc_we,
	output reg ra_we,
	output reg rb_we,
	output reg rz_we,
	output reg rd_we,
	output reg rw_we, //memory
	output reg rf_we  //register file
);

	localparam FETCH = 3'b000;
	localparam DECODE = 3'b001;
	localparam EXECUTE = 3'b010;
	localparam MEMORY = 3'b011;
	localparam WRITEBACK = 3'b111;

	reg [2:0] state = 3'b000;
	
	// sequential
   always @(posedge clk) begin
		if (reset)
			state <= FETCH;
		else
			state <= (state == WRITEBACK) ? FETCH : state + 3'b1;
   end
	 
	//combinational
	always @(*) begin
		ir_we = 1'b0;
		pc_we = 1'b0;
		ra_we = 1'b0;
		rb_we = 1'b0;
		rz_we = 1'b0;
		rd_we = 1'b0;
		rw_we = 1'b0;
		rf_we = 1'b0;
		
		case(state) 
			FETCH: begin
				ir_we = 1'b1;
				pc_we = 1'b1;
			end
			
			DECODE: begin
				ra_we = 1'b1;
				rb_we = 1'b1;
			end
			
			EXECUTE: begin
				rz_we = 1'b1;
				rd_we = 1'b1;
				//pc_we = 1'b1; //temp
			end
			
			MEMORY: rw_we = 1'b1;
			
			WRITEBACK: begin
				rf_we = 1'b1;
			end
		
		endcase
		
		state <= (state == WRITEBACK) ? FETCH : state + 1'b1;
	end
endmodule
		