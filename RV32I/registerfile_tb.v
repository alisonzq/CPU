`timescale 1ns/1ps

module registerfile_tb;

    reg         clk;
    reg         reset;
    reg         we;
    reg  [4:0]  rs1_addr, rs2_addr, rd_addr;
    reg  [31:0] rd_data;
    wire [31:0] rs1_data, rs2_data;

    integer errors = 0;
    integer tests  = 0;

    registerfile dut (
        .clk      (clk),
        .reset      (reset),
        .we       (we),
        .rs1_addr (rs1_addr),
        .rs2_addr (rs2_addr),
        .rd_addr  (rd_addr),
        .rd_data  (rd_data),
        .rs1_data (rs1_data),
        .rs2_data (rs2_data)
    );

    // 10ns clock period
    always #5 clk = ~clk;

    // checks rs1_data against an expected value for a given read address
    task check_rs1;
        input [4:0]  addr;
        input [31:0] expected;
        begin
            rs1_addr = addr;
            #1; // let the combinational read settle
            tests = tests + 1;
            if (rs1_data !== expected) begin
                errors = errors + 1;
                $display("FAIL [%0d] read x%0d -> rs1_data=%h (expected %h)",
                          tests, addr, rs1_data, expected);
            end else begin
                $display("PASS [%0d] read x%0d -> rs1_data=%h",
                          tests, addr, rs1_data);
            end
        end
    endtask

    // performs a single synchronous write: assert we/rd_addr/rd_data across
    // one clock edge, then deassert we
    task write_reg;
        input [4:0]  addr;
        input [31:0] data;
        begin
            @(negedge clk);
            we      = 1'b1;
            rd_addr = addr;
            rd_data = data;
            @(posedge clk);   // write commits here
            @(negedge clk);
            we      = 1'b0;
        end
    endtask

    initial begin
        $display("---- regfile testbench start ----");
        clk      = 0;
        reset    = 1;
        we       = 0;
        rs1_addr = 0;
        rs2_addr = 0;
        rd_addr  = 0;
        rd_data  = 0;

        // hold reset across a couple of clock edges
        @(negedge clk);
        @(negedge clk);
        reset = 0;

        // Test: after reset, all registers read as 0
        check_rs1(5'd5,  32'h0);
        check_rs1(5'd31, 32'h0);

        // Test: write x5, then read it back
        write_reg(5'd5, 32'hDEADBEEF);
        check_rs1(5'd5, 32'hDEADBEEF);

        // Test: writes to x0 are ignored -- it still reads as 0
        write_reg(5'd0, 32'hFFFFFFFF);
        check_rs1(5'd0, 32'h0);

        // Test: writing a different register doesn't disturb x5
        write_reg(5'd10, 32'h12345678);
        check_rs1(5'd5,  32'hDEADBEEF);
        check_rs1(5'd10, 32'h12345678);

        // Test: both read ports work independently and simultaneously
        rs1_addr = 5'd5;
        rs2_addr = 5'd10;
        #1;
        tests = tests + 1;
        if (rs1_data !== 32'hDEADBEEF || rs2_data !== 32'h12345678) begin
            errors = errors + 1;
            $display("FAIL [%0d] dual read x5/x10 -> rs1=%h rs2=%h",
                      tests, rs1_data, rs2_data);
        end else begin
            $display("PASS [%0d] dual read x5/x10 -> rs1=%h rs2=%h",
                      tests, rs1_data, rs2_data);
        end

        // Test: we=0 means no write happens, even with rd_addr/rd_data driven
        @(negedge clk);
        we      = 1'b0;
        rd_addr = 5'd5;
        rd_data = 32'h00000000;
        @(posedge clk);
        @(negedge clk);
        check_rs1(5'd5, 32'hDEADBEEF); // unchanged

        // Test: both read ports pointed at the same address agree
        rs1_addr = 5'd10;
        rs2_addr = 5'd10;
        #1;
        tests = tests + 1;
        if (rs1_data !== rs2_data) begin
            errors = errors + 1;
            $display("FAIL [%0d] same-address dual read mismatch: rs1=%h rs2=%h",
                      tests, rs1_data, rs2_data);
        end else begin
            $display("PASS [%0d] same-address dual read match: rs1=%h rs2=%h",
                      tests, rs1_data, rs2_data);
        end

        $display("---- regfile testbench done: %0d tests, %0d errors ----", tests, errors);
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TEST(S) FAILED", errors);

        $finish;
    end

endmodule
