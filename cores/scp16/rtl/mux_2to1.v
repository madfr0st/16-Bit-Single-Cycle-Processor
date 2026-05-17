// =============================================================================
// mux_2to1.v  --  16-bit 2:1 multiplexer
// =============================================================================
// sel = 0  ->  out = in0
// sel = 1  ->  out = in1
// =============================================================================
`timescale 1ns / 1ps

module mux_2to1 (
    input  wire [15:0] in0,
    input  wire [15:0] in1,
    input  wire        sel,
    output wire [15:0] out
);

    assign out = sel ? in1 : in0;

endmodule
