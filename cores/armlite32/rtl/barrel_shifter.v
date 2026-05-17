// =============================================================================
// barrel_shifter.v  --  the ARM Operand2 generator
// =============================================================================
// In real ARM, Operand2 is one of:
//   * immediate form: an 8-bit immediate rotated right by 2*rot bits
//   * register  form: Rm shifted by either an immediate amount or by Rs[7:0],
//                     using one of LSL/LSR/ASR/ROR
//
// We support:
//   * Immediate form with rotate (matches DP_IMM encoding)
//   * Register form with immediate shift amount  (matches DP_REG encoding)
//
// This is what gives ARM its compact "free shift" inside data-processing
// instructions -- e.g. ADD R0, R1, R2 LSL #3 in a single 32-bit word.
// =============================================================================
`timescale 1ns / 1ps

`include "defines.v"

module barrel_shifter (
    input  wire        is_imm,          // 1 -> immediate form, 0 -> register form
    input  wire [31:0] rm_data,         // register-form input value
    input  wire [4:0]  shift_amount,    // register-form shift count
    input  wire [1:0]  shift_type,      // register-form shift kind
    input  wire [3:0]  imm_rot,         // immediate-form rotate count (* 2)
    input  wire [7:0]  imm8,            // immediate-form 8-bit value
    output reg  [31:0] op2
);

    reg [31:0] imm_expanded;
    integer    rotsh;

    always @(*) begin
        if (is_imm) begin
            // Rotate-right by (2 * imm_rot) of the zero-extended imm8
            rotsh        = imm_rot * 2;
            imm_expanded = {24'h0, imm8};
            // Conceptually:  op2 = ROR(imm_expanded, rotsh)
            op2 = (imm_expanded >> rotsh) | (imm_expanded << (32 - rotsh));
            if (rotsh == 0) op2 = imm_expanded;
        end
        else begin
            case (shift_type)
                `SH_LSL: op2 = rm_data << shift_amount;
                `SH_LSR: op2 = rm_data >> shift_amount;
                `SH_ASR: op2 = $signed(rm_data) >>> shift_amount;
                `SH_ROR: op2 = (shift_amount == 0)
                              ? rm_data
                              : ((rm_data >> shift_amount) |
                                 (rm_data << (32 - shift_amount)));
            endcase
        end
    end

endmodule
