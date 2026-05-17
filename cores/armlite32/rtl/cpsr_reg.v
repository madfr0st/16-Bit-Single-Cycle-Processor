// =============================================================================
// cpsr_reg.v  --  the CPSR (current program status register) for armlite32
// =============================================================================
// We only model the 4 condition flags {N, Z, C, V}. Real ARM CPSR also holds
// the processor mode, I/F interrupt-disable bits, T (Thumb), etc.; those are
// out of scope here.
//
// Updated on a clock edge whenever `update` is high (the data-processing
// instruction had its S bit set, or it was TST/TEQ/CMP/CMN which always
// update flags).
// =============================================================================
`timescale 1ns / 1ps

module cpsr_reg (
    input  wire       clk,
    input  wire       rst,
    input  wire       update,
    input  wire [3:0] flags_in,
    output reg  [3:0] flags_out
);

    always @(posedge clk or posedge rst) begin
        if (rst)         flags_out <= 4'h0;
        else if (update) flags_out <= flags_in;
    end

endmodule
