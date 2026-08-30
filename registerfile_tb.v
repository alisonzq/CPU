`timescale 1ns / 1ps
//
// Testbench for the RegisterFile module (Task 2).
//
module registerfile_tb;

    reg         clk;
    reg         reset;
    reg         we;
    reg  [2:0]  Addr_A, Addr_B, Addr_C;
    reg  [15:0] C;
    wire [15:0] A, B;

    integer checks = 0;
    integer errors = 0;
    integer k;

    reg [15:0] ref_regs [0:7];

    // NOTE: change "registerfile" here if you rename/re-case your module.
    registerfile dut (
        .clk(clk), .reset(reset), .we(we),
        .Addr_A(Addr_A), .Addr_B(Addr_B), .Addr_C(Addr_C),
        .C(C), .A(A), .B(B)
    );

    // The 16-entry stimulus, taken verbatim from the RegisterFileTester
    // ROMs in cpu.circ.
    reg [2:0]  addr_a_rom [0:15];
    reg [2:0]  addr_b_rom [0:15];
    reg [2:0]  addr_c_rom [0:15];
    reg        we_rom     [0:15];
    reg [15:0] c_rom      [0:15];

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        addr_a_rom[0]=3'd5;  addr_a_rom[1]=3'd2;  addr_a_rom[2]=3'd7;  addr_a_rom[3]=3'd3;
        addr_a_rom[4]=3'd2;  addr_a_rom[5]=3'd0;  addr_a_rom[6]=3'd2;  addr_a_rom[7]=3'd6;
        addr_a_rom[8]=3'd2;  addr_a_rom[9]=3'd4;  addr_a_rom[10]=3'd1; addr_a_rom[11]=3'd3;
        addr_a_rom[12]=3'd5; addr_a_rom[13]=3'd5; addr_a_rom[14]=3'd2; addr_a_rom[15]=3'd6;

        addr_b_rom[0]=3'd4;  addr_b_rom[1]=3'd4;  addr_b_rom[2]=3'd6;  addr_b_rom[3]=3'd0;
        addr_b_rom[4]=3'd2;  addr_b_rom[5]=3'd3;  addr_b_rom[6]=3'd5;  addr_b_rom[7]=3'd5;
        addr_b_rom[8]=3'd5;  addr_b_rom[9]=3'd0;  addr_b_rom[10]=3'd0; addr_b_rom[11]=3'd4;
        addr_b_rom[12]=3'd5; addr_b_rom[13]=3'd3; addr_b_rom[14]=3'd7; addr_b_rom[15]=3'd5;

        addr_c_rom[0]=3'd0;  addr_c_rom[1]=3'd5;  addr_c_rom[2]=3'd0;  addr_c_rom[3]=3'd5;
        addr_c_rom[4]=3'd5;  addr_c_rom[5]=3'd7;  addr_c_rom[6]=3'd2;  addr_c_rom[7]=3'd3;
        addr_c_rom[8]=3'd6;  addr_c_rom[9]=3'd4;  addr_c_rom[10]=3'd0; addr_c_rom[11]=3'd4;
        addr_c_rom[12]=3'd7; addr_c_rom[13]=3'd7; addr_c_rom[14]=3'd4; addr_c_rom[15]=3'd6;

        we_rom[0]=1'b0; we_rom[1]=1'b0; we_rom[2]=1'b0; we_rom[3]=1'b1;
        we_rom[4]=1'b0; we_rom[5]=1'b0; we_rom[6]=1'b1; we_rom[7]=1'b0;
        we_rom[8]=1'b0; we_rom[9]=1'b0; we_rom[10]=1'b1; we_rom[11]=1'b1;
        we_rom[12]=1'b0; we_rom[13]=1'b0; we_rom[14]=1'b1; we_rom[15]=1'b1;

        c_rom[0]=16'h0001;  c_rom[1]=16'h0004;  c_rom[2]=16'h000C;  c_rom[3]=16'h000F;
        c_rom[4]=16'h0000;  c_rom[5]=16'h0005;  c_rom[6]=16'h0009;  c_rom[7]=16'h0007;
        c_rom[8]=16'h000C;  c_rom[9]=16'h000B;  c_rom[10]=16'h0009; c_rom[11]=16'h000F;
        c_rom[12]=16'h000B; c_rom[13]=16'h0009; c_rom[14]=16'h0001; c_rom[15]=16'h000E;

        for (k = 0; k < 8; k = k + 1)
            ref_regs[k] = 16'h0000;

        // reset pulse
        reset = 1'b1; we = 1'b0; Addr_A = 0; Addr_B = 0; Addr_C = 0; C = 0;
        @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        // replay the 16-cycle stimulus
        for (k = 0; k < 16; k = k + 1) begin
            Addr_A = addr_a_rom[k];
            Addr_B = addr_b_rom[k];
            Addr_C = addr_c_rom[k];
            we     = we_rom[k];
            C      = c_rom[k];
            #1; // let the combinational reads settle

            checks = checks + 1;
            if (A !== ref_regs[Addr_A] || B !== ref_regs[Addr_B]) begin
                errors = errors + 1;
                $display("FAIL cycle %0d: Addr_A=%0d Addr_B=%0d | got A=%h B=%h | exp A=%h B=%h",
                          k, Addr_A, Addr_B, A, B, ref_regs[Addr_A], ref_regs[Addr_B]);
            end

            @(posedge clk);
            if (we_rom[k])
                ref_regs[addr_c_rom[k]] = c_rom[k]; // mirror the write into the reference model
            @(negedge clk);
        end

        // final readback: every register, one at a time, including R0 --
        // this is what catches a "register 0 is hardwired to zero" bug.
        we = 1'b0;
        for (k = 0; k < 8; k = k + 1) begin
            Addr_A = k;
            Addr_B = k;
            #1;
            checks = checks + 1;
            if (A !== ref_regs[k] || B !== ref_regs[k]) begin
                errors = errors + 1;
                $display("FAIL readback R%0d: got A=%h B=%h | exp %h", k, A, B, ref_regs[k]);
            end
            @(posedge clk);
            @(negedge clk);
        end

        if (errors == 0)
            $display("ALL %0d CHECKS PASSED", checks);
        else
            $display("%0d of %0d CHECKS FAILED", errors, checks);

        $finish;
    end

endmodule