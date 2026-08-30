module cpu #(
    parameter MEM_FILE = ""
)(
    input  wire clk,
    input  wire reset,
    output wire [47:0] cpu_out,
    output wire halt
);

	reg [15:0] PC, IR,  RA, RB, RZ, RW, RD;

	wire [1:0] op_code = IR[15:14];
	wire [2:0] alu_fun = IR[13:11];
	wire 		  I_bit = IR[10];
	wire [2:0] addr_c = IR[9:7];
	wire [2:0] addr_a = IR[6:4];
	wire [15:0] imm_ext = {{12{IR[3]}}, IR[3:0]}; // sign-extend the 4-bit immediate
	
	wire is_load = (op_code == 2'b10);
	wire is_store = (op_code == 2'b11);
	wire writes_back = (op_code == 2'b00) || is_load;
	wire [2:0] addr_b_sel = is_store ? IR[9:7] : IR[2:0];
	wire is_branch = (op_code == 2'b01);
	wire [2:0] alu_fun_sel = is_branch ? 3'b001 : alu_fun;
	wire negative, carry, zero, overflow;
	wire [15:0] regfile_A, regfile_B; 
	wire cond_result;
	wire ir_we, pc_we, ra_we, rb_we, rz_we, rd_we, rw_we, rf_we;
	wire [15:0] instr_word;
	wire [15:0] alu_b_in = I_bit ? imm_ext : RB;
	wire [15:0] data_word;
	wire [15:0] alu_c;
	wire is_branch_taken = is_branch && cond_result && rz_we; //rz only high on execute

	condition_encoding cond_inst (
		.Z (zero),
		.N (negative),
		.V (overflow),
		.condition (alu_fun),
		.C (cond_result)
	);
		
	//control_fsm instance
	control_fsm fsm_inst (
		 .clk   (clk),
		 .reset (reset),
		 .writes_back (writes_back),
		 .is_branch_taken (is_branch_taken),
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
	ins_mem #(
		 .MEM_FILE(MEM_FILE)   // forwarding cpu's own MEM_FILE parameter through
	) imem_inst (
		 .addr (PC),
		 .data (instr_word)
	);
	
	//data memory instance
	data_mem dmem_inst (
		.clk (clk),
		.we (is_store && rw_we),
		.addr (alu_c),
		.data_in (RD),
		.data_out (data_word)
	);
	
	//alu instance
	alu alu_inst (
		.A (RA),
		.B (alu_b_in),
		.fun (alu_fun_sel),
		.C (alu_c),
		.negative (negative),
		.carry (carry),
		.zero (zero),
		.overflow (overflow)
	);
	
	//register file instance
	registerfile rf_inst (
		.clk (clk),
		.reset (reset),
		.we(rf_we),
		.Addr_A (addr_a),
		.Addr_B (addr_b_sel),
		.Addr_C (addr_c),
		.C (RW),
		.A (regfile_A),
		.B (regfile_B)
	);	
	
	always @(posedge clk) begin
		if (reset) PC <= 16'h0000; 
		else if (pc_we) begin
			if (is_branch_taken) PC <= PC + {{13{IR[9]}}, IR[9:7]};
			else PC <= PC + 16'h0001;
		end
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

	always @(posedge clk) begin
		if (reset) RD <= 16'h0000;
		else if (rd_we) RD <= RB;
	end
	
	always @(posedge clk) begin
		if (reset) RW <= 16'h0000;
		else if (rw_we) RW <= is_load ? data_word : RZ;
	end
	
	assign halt = (IR == 16'h4380);
	assign cpu_out = {PC, IR, RZ}; // bits 47:32=PC, 31:16=IR, 15:0=RZ, per spec
	
endmodule