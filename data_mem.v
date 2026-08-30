module data_mem #(
    parameter MEM_FILE = ""   // optional preload; usually left empty since programs build up data memory themselves via stores, unlike ins_mem's program image
)(
    input  wire clk,
    input  wire we,
    input  wire [15:0] addr,
    input  wire [15:0] data_in,
    output wire [15:0] data_out
);

   reg [15:0] mem [0:65535];   // 64K words, each 16 bits
	
	initial begin
		if (MEM_FILE != "")
			$readmemh(MEM_FILE, mem);
	end
	
	always @(posedge clk) begin
		if(we) mem[addr] <= data_in;
	end
	
	assign data_out = mem[addr];
	
endmodule