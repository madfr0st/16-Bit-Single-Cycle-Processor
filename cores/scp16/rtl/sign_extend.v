// =============================================================================
// sign_extend.v  --  4-bit -> 16-bit sign extension
// =============================================================================
// Replicates bit[3] twelve times to the left so that, e.g.,
//   4'b1111  -> 16'hFFFF  ( -1 )
//   4'b0111  -> 16'h0007  ( +7 )
// =============================================================================
`timescale 1ns / 1ps

module sign_extend (
    input  wire [3:0]  in,
    output wire [15:0] out
);

    assign out = {{12{in[3]}}, in};

endmodule
