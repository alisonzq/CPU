// Simple traffic light FSM: GREEN -> YELLOW -> RED -> GREEN ...
// Each state lasts a fixed number of clock cycles (tiny numbers here so
// simulation is fast; in real life a clock divider would make these
// actual seconds).
//
// This introduces the two things every clocked design needs:
//   1. State held in a register (state), updated only on posedge clk
//   2. Synchronous reset, so the design starts from a known state

module traffic_fsm (
    input  wire clk,
    input  wire rst,       // synchronous, active-high
    output reg  [1:0] light // 2'b00=RED, 2'b01=GREEN, 2'b10=YELLOW
);

    localparam RED    = 2'b00;
    localparam GREEN  = 2'b01;
    localparam YELLOW = 2'b10;

    localparam RED_TIME    = 4;
    localparam GREEN_TIME  = 4;
    localparam YELLOW_TIME = 2;

    reg [1:0] state;
    reg [3:0] counter;

    always @(posedge clk) begin
        if (rst) begin
            state   <= RED;
            counter <= 0;
        end else begin
            case (state)
                RED: begin
                    if (counter == RED_TIME - 1) begin
                        state   <= GREEN;
                        counter <= 0;
                    end else
                        counter <= counter + 1;
                end
                GREEN: begin
                    if (counter == GREEN_TIME - 1) begin
                        state   <= YELLOW;
                        counter <= 0;
                    end else
                        counter <= counter + 1;
                end
                YELLOW: begin
                    if (counter == YELLOW_TIME - 1) begin
                        state   <= RED;
                        counter <= 0;
                    end else
                        counter <= counter + 1;
                end
                default: state <= RED;
            endcase
        end
    end

    // Output logic: light mirrors current state directly (a "Moore" FSM,
    // meaning output depends only on state, not on inputs)
    always @(*) begin
        light = state;
    end

endmodule
