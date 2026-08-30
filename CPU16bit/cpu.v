module cpu #(
    parameter MEM_FILE = ""
)(
    input  wire clk,
    input  wire reset,
    output wire [47:0] cpu_out,
    output wire halt
);

	reg [15:0] PC, IR,  RA, RB, RZ;

	wire [2:0] alu_fun = IR[13:11];
	wire 		  I_bit = IR[10];
	wire [2:0] addr_c = IR[9:7];
	wire [2:0] addr_a = IR[6:4];
	wire [2:0] addr_b = IR[2:0]; // low 3 bits of the 4-bit Op2 field
	wire [15:0] imm_ext = {{12{IR[3]}}, IR[3:0]}; // sign-extend the 4-bit immediate
	
	//control_fsm instance
	wire ir_we, pc_we, ra_we, rb_we, rz_we, rd_we, rw_we, rf_we;
	control_fsm fsm_inst (
		 .clk   (clk),
		 .reset (reset),
		 .ir_we (ir_we),
		 .pc_we (pc_we),
		 .ra_we (ra_we),
		 .rb_we (rb_we),
		 .rz_we (rz_we),
		 .rd_we (rd_we),
		 .rw_we (rw_we),
		 .rf_we (rf_we)
	);
	
	//instruction memory instance
	wire [15:0] instr_word;
	ins_mem #(
		 .MEM_FILE(MEM_FILE)   // forwarding cpu's own MEM_FILE parameter through
	) imem_inst (
		 .addr (PC),
		 .data (instr_word)
	);
	
	//alu instance
	wire [15:0] alu_b_in = I_bit ? imm_ext : RB;
	wire [15:0] alu_c;
	wire negative, carry, zero, overflow;
	alu alu_inst (
		.A (RA),
		.B (alu_b_in),
		.fun (alu_fun),
		.C (alu_c),
		.negative (negative),
		.carry (carry),
		.zero (zero),
		.overflow (overflow)
	);
	
	//register file instance
	wire [15:0] regfile_A, regfile_B; 
	registerfile rf_inst (
		.clk (clk),
		.reset (reset),
		.we(rf_we),
		.Addr_A (addr_a),
		.Addr_B (addr_b),
		.Addr_C (addr_c),
		.C (RZ),
		.A (regfile_A),
		.B (regfile_B)
	);	
	

	always @(posedge clk) begin
		if (reset) PC <= 16'h0000;
		else if (pc_we) PC <= PC + 16'h0001;
	end
	
	always @(posedge clk) begin
		if (reset) IR <= 16'h0000;
		else if (ir_we) IR <= instr_word;
	end
	
	always @(posedge clk) begin
		if (reset)  begin
			RA <= 16'h0000;
			RB <= 16'h0000;
		end else begin
			if (ra_we) RA <= regfile_A;
			if (rb_we) RB <= regfile_B;
		end
	end
	
	always @(posedge clk) begin
		if (reset) RZ <= 16'h0000;
		else if (rz_we) RZ <= alu_c;
	end
	
	
	assign halt = (IR == 16'h4380);
	assign cpu_out = {PC, IR, RZ}; // bits 47:32=PC, 31:16=IR, 15:0=RZ, per spec
	
endmodule