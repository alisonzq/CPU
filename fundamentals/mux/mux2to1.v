// 2-to-1 multiplexer
// Selects between two inputs (a, b) based on sel
module mux2to1 (
    input  wire a,
    input  wire b,
    input  wire sel,
    output wire y
);

    // Pure combinational logic: no clock, output reacts instantly to inputs
    assign y = sel ? b : a;

endmodule
