module ins_mem #(
    parameter MEM_FILE = ""   // path to a $readmemh-format file; empty = leave uninitialized
)(
    input  wire [15:0] addr,  // this is PC directly -- a word address, not a byte address
    output wire [15:0] data   // instruction at that address, available combinationally
);
	
   reg [15:0] mem [0:65535];   // 64K words, each 16 bits
	
	initial begin
		if (MEM_FILE != 0)
			$readmemh(MEM_FILE, mem);
	end
	
	assign data = mem[addr];
	
endmodule