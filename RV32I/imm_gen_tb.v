`timescale 1ns/1ps

module imm_gen_tb;

    reg  [31:0] instruction;
    wire [31:0] immediate;

    integer errors = 0;
    integer tests  = 0;

    imm_gen dut (
        .instruction (instruction),
        .immediate   (immediate)
    );

    localparam OPCODE_ITYPE  = 7'b0010011;
    localparam OPCODE_LOAD   = 7'b0000011;
    localparam OPCODE_JALR   = 7'b1100111;
    localparam OPCODE_STORE  = 7'b0100011;
    localparam OPCODE_BRANCH = 7'b1100011;
    localparam OPCODE_LUI    = 7'b0110111;
    localparam OPCODE_AUIPC  = 7'b0010111;
    localparam OPCODE_JAL    = 7'b1101111;

    // ---- instruction-encoding helpers ----
    // Each function packs a target offset into the scattered bit positions
    // its format actually uses in a real RV32I instruction word -- i.e.
    // each one is the exact inverse of what imm_gen is supposed to do for
    // that format, built independently from the DUT so a real decode bug
    // in the DUT will show up as a mismatch rather than being hidden.

    function [31:0] make_itype;
        input [11:0] imm12;
        input [4:0]  rs1;
        input [2:0]  funct3;
        input [4:0]  rd;
        input [6:0]  opc;
        begin
            make_itype = {imm12, rs1, funct3, rd, opc};
        end
    endfunction

    function [31:0] make_stype;
        input [11:0] imm12;
        input [4:0]  rs2;
        input [4:0]  rs1;
        input [2:0]  funct3;
        input [6:0]  opc;
        begin
            make_stype = {imm12[11:5], rs2, rs1, funct3, imm12[4:0], opc};
        end
    endfunction

    function [31:0] make_btype;
        input [12:0] imm13; // bit 0 must be 0 -- branch offsets are even
        input [4:0]  rs2;
        input [4:0]  rs1;
        input [2:0]  funct3;
        input [6:0]  opc;
        begin
            make_btype = {imm13[12], imm13[10:5], rs2, rs1, funct3, imm13[4:1], imm13[11], opc};
        end
    endfunction

    function [31:0] make_utype;
        input [19:0] imm20;
        input [4:0]  rd;
        input [6:0]  opc;
        begin
            make_utype = {imm20, rd, opc};
        end
    endfunction

    function [31:0] make_jtype;
        input [20:0] imm21; // bit 0 must be 0 -- jump offsets are even
        input [4:0]  rd;
        input [6:0]  opc;
        begin
            make_jtype = {imm21[20], imm21[10:1], imm21[11], imm21[19:12], rd, opc};
        end
    endfunction

    task check;
        input [31:0]  expected;
        input [127:0] label;
        begin
            #1;
            tests = tests + 1;
            if (immediate !== expected) begin
                errors = errors + 1;
                $display("FAIL [%0d] %0s: instruction=%h -> immediate=%h (expected %h)",
                          tests, label, instruction, immediate, expected);
            end else begin
                $display("PASS [%0d] %0s: instruction=%h -> immediate=%h",
                          tests, label, instruction, immediate);
            end
        end
    endtask

    initial begin
        $display("---- imm_gen testbench start ----");

        // I-type: addi x5, x1, 5
        instruction = make_itype(12'd5, 5'd1, 3'b000, 5'd5, OPCODE_ITYPE);
        check(32'sd5, "I-type +5");

        // I-type negative: addi x5, x1, -1
        instruction = make_itype(-12'sd1, 5'd1, 3'b000, 5'd5, OPCODE_ITYPE);
        check(-32'sd1, "I-type -1");

        // Load: lw x3, 100(x2)
        instruction = make_itype(12'd100, 5'd2, 3'b010, 5'd3, OPCODE_LOAD);
        check(32'sd100, "LOAD +100");

        // JALR: jalr x1, 4(x2)
        instruction = make_itype(12'd4, 5'd2, 3'b000, 5'd1, OPCODE_JALR);
        check(32'sd4, "JALR +4");

        // Store: sw x5, 20(x2)
        instruction = make_stype(12'd20, 5'd5, 5'd2, 3'b010, OPCODE_STORE);
        check(32'sd20, "STORE +20");

        // Store negative: sw x5, -4(x2)
        instruction = make_stype(-12'sd4, 5'd5, 5'd2, 3'b010, OPCODE_STORE);
        check(-32'sd4, "STORE -4");

        // Branch: beq x1, x2, +8
        instruction = make_btype(13'd8, 5'd2, 5'd1, 3'b000, OPCODE_BRANCH);
        check(32'sd8, "BRANCH +8");

        // Branch negative: bne x1, x2, -4
        instruction = make_btype(-13'sd4, 5'd2, 5'd1, 3'b001, OPCODE_BRANCH);
        check(-32'sd4, "BRANCH -4");

        // LUI: lui x5, 0x12345
        instruction = make_utype(20'h12345, 5'd5, OPCODE_LUI);
        check(32'h12345000, "LUI 0x12345");

        // AUIPC: auipc x6, 0xFFFFF
        instruction = make_utype(20'hFFFFF, 5'd6, OPCODE_AUIPC);
        check(32'hFFFFF000, "AUIPC 0xFFFFF");

        // JAL: jal x1, +16
        instruction = make_jtype(21'd16, 5'd1, OPCODE_JAL);
        check(32'sd16, "JAL +16");

        // JAL negative: jal x1, -16
        instruction = make_jtype(-21'sd16, 5'd1, OPCODE_JAL);
        check(-32'sd16, "JAL -16");

        // R-type: opcode not in the case list -> default, immediate should be 0
        instruction = {7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, 7'b0110011}; // add x3,x1,x2
        check(32'h00000000, "R-type default");

        $display("---- imm_gen testbench done: %0d tests, %0d errors ----", tests, errors);
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TEST(S) FAILED", errors);

        $finish;
    end

endmodule