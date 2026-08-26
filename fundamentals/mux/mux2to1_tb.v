`timescale 1ns/1ps

module mux2to1_tb;

	reg a, b, sel;
	wire y;
	initial begin
		 $dumpfile("mux.vcd");
		 $dumpvars(0, mux2to1_tb);
	end

	
	// Instantiate the design under test (DUT)
	mux2to1 dut (
		.a(a),
		.b(b),
		.sel(sel),	
		.y(y)
	);

	integer i;

	initial begin
		$display("a b sel | y");
		$monitor("a=%b b=%b sel=%b y=%b", a, b, sel, y);

		for (i = 0; i < 8; i = i + 1) begin
			{a, b, sel} = i;
			#1;
		end

		$finish;
	end

endmodule

