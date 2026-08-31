module cpu #(
    parameter MEM_FILE = ""
)(
    input  wire clk,
    input  wire reset,
    output wire [47:0] cpu_out,
    output wire halt
);

	reg [15:0] PC, IR, RA, RB, RZ, RW, RD;
	
	//Decode
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
	
	wire negative, carry, zero, overflow;
	wire negative_branch, carry_branch, zero_branch, overflow_branch;
	wire [15:0] regfile_A, regfile_B; 
	wire cond_result;
	wire [15:0] instr_word;
	wire [15:0] data_word;
	wire [15:0] alu_c;
	
	//comparator at decode stage
	wire [15:0] decode_sub      = regfile_A - regfile_B;
	wire        decode_zero     = (decode_sub == 16'h0000);
	wire        decode_negative = decode_sub[15];
	wire        decode_overflow = (regfile_A[15] != regfile_B[15]) && (decode_sub[15] != regfile_A[15]);
	wire decode_cond_result;

	//Execute
	reg is_load_ex, is_store_ex, writes_back_ex, is_branch_ex, I_bit_ex;
	reg [2:0] addr_c_ex;
	reg [2:0] alu_fun_ex;
	reg [15:0] imm_ext_ex;
	wire [2:0] alu_fun_sel = is_branch_ex ? 3'b001 : alu_fun_ex;
	reg [2:0] addr_a_ex;
	reg [2:0] addr_b_sel_ex;
	
	wire is_branch_taken = is_branch && decode_cond_result;	
	wire [15:0] target = PC + {{13{addr_c[2]}}, addr_c}; //displacement of producer 
	
	//Memory
	reg is_load_mem, is_store_mem, writes_back_mem, is_branch_mem;
	reg [2:0] addr_c_mem;
	
	//Write Back
	reg writes_back_wb;
	reg [2:0] addr_c_wb;

	//stalling
	wire stall = (writes_back_ex  && is_load_ex && (addr_c_ex  == addr_a || addr_c_ex  == addr_b_sel)) //e.g. stalls until wb if producer is a load 
				  || (is_branch && writes_back_ex && (addr_c_ex  == addr_a || addr_c_ex  == addr_b_sel)) //branch stalling on a plain ALU producer sitting at execute at gap=0
				  || (is_branch && writes_back_mem && (addr_c_mem == addr_a || addr_c_mem == addr_b_sel)) //branch doesn't reach compute for comparison, forwarding path unavailable
				  || (writes_back_wb  && (addr_c_wb  == addr_a || addr_c_wb  == addr_b_sel)); //producer is in wb while consumer is still in decode, still need one stall cycle 
	
	//forwarding
	wire fwd_mem_a = writes_back_mem && !is_load_mem && (addr_c_mem == addr_a_ex);
	wire fwd_mem_b = writes_back_mem && !is_load_mem && (addr_c_mem == addr_b_sel_ex) && !I_bit_ex;
	
	wire fwd_wb_a = !fwd_mem_a && writes_back_wb && (addr_c_wb == addr_a_ex);
	wire fwd_wb_b = !fwd_mem_b && writes_back_wb && (addr_c_wb == addr_b_sel_ex) && !I_bit_ex;

	wire [15:0] alu_a_sel = fwd_mem_a ? RZ : (fwd_wb_a ? RW : RA);
	wire [15:0] alu_b_sel = I_bit_ex ? imm_ext_ex : (fwd_mem_b ? RZ : (fwd_wb_b ? RW : RB));
	
	condition_encoding cond_inst (
		.Z (zero),
		.N (negative),
		.V (overflow),
		.condition (alu_fun_sel),
		.C (cond_result)
	);
	
	condition_encoding cond_inst_decode (
		.Z (decode_zero),
		.N (decode_negative),
		.V (decode_overflow),
		.condition (alu_fun),
		.C (decode_cond_result)
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
		.we (is_store_mem),
		.addr (RZ),
		.data_in (RD),
		.data_out (data_word)
	);
	
	//alu instance
	alu alu_inst (
		.A (alu_a_sel),
		.B (alu_b_sel),
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
		.we(writes_back_wb),
		.Addr_A (addr_a),
		.Addr_B (addr_b_sel),
		.Addr_C (addr_c_wb),
		.C (RW),
		.A (regfile_A),
		.B (regfile_B)
	);	
	
	always @(posedge clk) begin
		if (reset) begin
			PC <= 16'h0000;
			IR <= 16'h0000;
		end else if (is_branch_taken) begin
			PC <= target;
			IR <= 16'h0000; //  what's after the branch should'nt make it to compute
		end else if (stall) begin //hold at stall
		end else begin
			PC <= PC + 16'h0001;
			IR <= instr_word;
		end
	end
	
	always @(posedge clk) begin
		if (reset)  begin
			RA <= 16'h0000;
			RB <= 16'h0000;
			is_load_ex <= 1'b0;
			is_store_ex <= 1'b0;
			writes_back_ex <= 1'b0;
			is_branch_ex <= 1'b0;
			I_bit_ex <= 1'b0;
			addr_c_ex <= 3'b000;
			alu_fun_ex <= 3'b000;
			imm_ext_ex <= 16'h0000;
			addr_a_ex <= 3'b000;
			addr_b_sel_ex <= 3'b000;
			
			is_load_mem <= 1'b0;
			is_store_mem <= 1'b0;
			writes_back_mem <= 1'b0;
			is_branch_mem <= 1'b0;
			addr_c_mem <= 3'b000;
			
			writes_back_wb <= 1'b0;
			addr_c_wb <= 3'b000;
		end else begin
			RA <= regfile_A;
			RB <= regfile_B;
			
			if (!stall) begin
				is_load_ex <= is_load;
				is_store_ex <= is_store;
				writes_back_ex <= writes_back;
				is_branch_ex <= is_branch;
				I_bit_ex <= I_bit;
				addr_c_ex <= addr_c;
				alu_fun_ex <= alu_fun;
				imm_ext_ex <= imm_ext;
				addr_a_ex <= addr_a;
				addr_b_sel_ex <= addr_b_sel;
			end else begin //bubble
				is_load_ex <= 1'b0;
				is_store_ex <= 1'b0;
				writes_back_ex <= 1'b0;
				is_branch_ex <= 1'b0;
				I_bit_ex <= 1'b0;
				addr_c_ex <= 3'b000;
				alu_fun_ex <= 3'b000;
				imm_ext_ex <= 16'h0000;
				addr_a_ex <= 3'b000;
				addr_b_sel_ex <= 3'b000;
			end
			
			is_load_mem <= is_load_ex;
			is_store_mem <= is_store_ex;
			writes_back_mem <= writes_back_ex;
			is_branch_mem <= is_branch_ex;
			addr_c_mem <= addr_c_ex;

			writes_back_wb <= writes_back_mem;
			addr_c_wb <= addr_c_mem;
		end
	end
	
	always @(posedge clk) begin
		if (reset) RZ <= 16'h0000;
		else RZ <= alu_c;
	end

	always @(posedge clk) begin
		if (reset) RD <= 16'h0000;
		else RD <= RB;
	end
	
	always @(posedge clk) begin
		if (reset) RW <= 16'h0000;
		else RW <= is_load_mem ? data_word : RZ;
	end
	
	assign halt = (IR == 16'h4380);
	assign cpu_out = {PC, IR, RZ}; // bits 47:32=PC, 31:16=IR, 15:0=RZ, per spec
	
endmodule