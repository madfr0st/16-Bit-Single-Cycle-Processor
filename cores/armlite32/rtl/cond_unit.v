// =============================================================================
// cond_unit.v  --  evaluates the 4-bit ARM condition code against CPSR flags
// =============================================================================
// Inputs are the current CPSR flag bits {N, Z, C, V} and the 4-bit cond from
// instruction[31:28]. Outputs 1 if the instruction should execute, 0 if it
// should be NOP-suppressed.
//
// This is the heart of ARM's "every instruction is conditional" idea.
// =============================================================================
`timescale 1ns / 1ps

`include "defines.v"

module cond_unit (
    input  wire [3:0] cond,
    input  wire [3:0] flags,    // {N, Z, C, V}
    output reg        execute
);

    wire n = flags[`FLAG_N];
    wire z = flags[`FLAG_Z];
    wire c = flags[`FLAG_C];
    wire v = flags[`FLAG_V];

    always @(*) begin
        case (cond)
            `COND_EQ: execute =  z;
            `COND_NE: execute = ~z;
            `COND_CS: execute =  c;
            `COND_CC: execute = ~c;
            `COND_MI: execute =  n;
            `COND_PL: execute = ~n;
            `COND_VS: execute =  v;
            `COND_VC: execute = ~v;
            `COND_HI: execute =  c & ~z;
            `COND_LS: execute = ~c |  z;
            `COND_GE: execute = (n == v);
            `COND_LT: execute = (n != v);
            `COND_GT: execute = ~z & (n == v);
            `COND_LE: execute =  z | (n != v);
            `COND_AL: execute = 1'b1;
            `COND_NV: execute = 1'b0;
        endcase
    end

endmodule
