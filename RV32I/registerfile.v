module registerfile (
	input wire clk,
	input wire reset,
	input wire we,
	input wire [4:0]  rs1_addr, // read port 1 address
   input wire [4:0]  rs2_addr, // read port 2 address
   input wire [4:0]  rd_addr, // write port address
   input wire [31:0] rd_data, // data to write into rd_addr
   output wire [31:0] rs1_data, // value read from rs1_addr
   output wire [31:0] rs2_data // value read from rs2_addr
);

	reg [31:0] registers [0:31];
	
	// reads are combinational (asynchronous) — x0 is hardwired to zero
	//assign implements read ports as combinational mux
	assign rs1_data = (rs1_addr == 5'd0) ? 32'b0 : registers[rs1_addr];
	assign rs2_data = (rs2_addr == 5'd0) ? 32'b0 : registers[rs2_addr];
	 
	// writes are synchronous, on the rising clock edge
	integer i;
	always @(posedge clk) begin
		if (reset) begin
			for (i = 0; i < 32; i = i + 1)
				registers[i] <= 32'b0;
		end else if (we && rd_addr != 5'd0) begin
			registers[rd_addr] <= rd_data;
		end
	end
	
endmodule 