`timescale 1ns/1ps

module traffic_fsm_tb;

    reg clk = 0;
    reg rst;
    wire [1:0] light;
    integer errors = 0;

    traffic_fsm dut (
        .clk(clk),
        .rst(rst),
        .light(light)
    );

    // Generate a clock: 10ns period (toggle every 5ns)
    always #5 clk = ~clk;

    initial begin
        $dumpfile("traffic_fsm.vcd");
        $dumpvars(0, traffic_fsm_tb);
    end

    // Expected sequence for RED_TIME=4, GREEN_TIME=4, YELLOW_TIME=2 (10 cycles per full loop)
    // cycle:  0  1  2  3 | 4  5  6  7 | 8  9
    // light: RED RED RED RED GRN GRN GRN GRN YEL YEL
    reg [1:0] expected [0:9];
    integer i;

    initial begin
        expected[0]=2'b00; expected[1]=2'b00; expected[2]=2'b00; expected[3]=2'b01;
        expected[4]=2'b01; expected[5]=2'b01; expected[6]=2'b01; expected[7]=2'b10;
        expected[8]=2'b10; expected[9]=2'b00;

        rst = 1;
        @(posedge clk); // apply reset for one cycle
        #1 rst = 0;     // deassert shortly AFTER the edge, avoiding a race
                         // with the DUT sampling rst at the same instant

        for (i = 0; i < 10; i = i + 1) begin
            @(posedge clk);
            #1; // let signals settle just after the clock edge
            if (light !== expected[i]) begin
                $display("FAIL: cycle=%0d light=%b (expected %b)", i, light, expected[i]);
                errors = errors + 1;
            end else begin
                $display("PASS: cycle=%0d light=%b", i, light);
            end
        end

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TEST(S) FAILED", errors);

        $finish;
    end

endmodule
