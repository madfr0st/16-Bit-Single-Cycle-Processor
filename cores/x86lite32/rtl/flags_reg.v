// =============================================================================
// flags_reg.v  --  EFLAGS-style flag register {OF, SF, ZF, CF}
// =============================================================================
// Latched at the rising clock edge whenever `update` is high. Reset clears all
// flags. Decoded condition tests are exposed as combinational outputs so the
// control unit / PC can decide branch_taken in the same cycle.
// =============================================================================
`timescale 1ns / 1ps

`include "defines.v"

module flags_reg (
    input  wire       clk,
    input  wire       rst,
    input  wire       update,
    input  wire [3:0] flags_in,    // {OF, SF, ZF, CF}

    output reg  [3:0] flags_out,
    // Decoded predicates used by the conditional-jump logic
    output wire       cond_e,      // JE   (ZF=1)
    output wire       cond_ne,     // JNE  (ZF=0)
    output wire       cond_g,      // JG   (ZF=0 & SF=OF)
    output wire       cond_l,      // JL   (SF!=OF)
    output wire       cond_ge,     // JGE  (SF=OF)
    output wire       cond_le      // JLE  (ZF=1 | SF!=OF)
);

    wire of = flags_out[`FLAG_OF];
    wire sf = flags_out[`FLAG_SF];
    wire zf = flags_out[`FLAG_ZF];

    assign cond_e  =  zf;
    assign cond_ne = ~zf;
    assign cond_g  = ~zf & (sf == of);
    assign cond_l  =  (sf != of);
    assign cond_ge =  (sf == of);
    assign cond_le =  zf | (sf != of);

    always @(posedge clk or posedge rst) begin
        if (rst)         flags_out <= 4'b0;
        else if (update) flags_out <= flags_in;
    end

endmodule
