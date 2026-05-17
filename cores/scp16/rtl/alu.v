// =============================================================================
// alu.v  --  16-bit ALU + branch comparator + branch/jump target adder
// =============================================================================
// In a textbook diagram the branch comparator and the PC-target adder are
// usually drawn as separate boxes. To keep the gate count low the design lets the
// single ALU do all three jobs; control signals pick which mode it's in.
//
// MODE 1: immi_enable = 1 (I-type / branches)
//   alu_op = 0000  ADDI / LW / SW    : result = b + c
//   alu_op = 0001  BEQ               : if (a == b) { result = pc + c; branch=1 }
//   alu_op = 0010  BNE               : if (a != b) { result = pc + c; branch=1 }
//
// MODE 2: immi_enable = 0 (R-type)
//   alu_op = 0000  ADD               : result = a + b
//   alu_op = 0001  SUB               : result = a - b
//   alu_op = 0010  SLL               : result = a << b
//   alu_op = 0011  AND               : result = a & b
//
// JUMP OVERRIDE
//   jmp = 1 unconditionally sets result = pc + jmp_diff (sign-extended 12-bit).
//   Control unit guarantees alu_op is don't-care in this mode.
// =============================================================================
`timescale 1ns / 1ps

module alu (
    input  wire [15:0] a,           // typically register Rd
    input  wire [15:0] b,           // typically register Rs
    input  wire [15:0] c,           // sign-extended 4-bit immediate
    input  wire [15:0] pc_out,      // current PC, for branch / jump targets
    input  wire [15:0] jmp_diff,    // sign-extended 12-bit jump offset
    input  wire [3:0]  alu_op,
    input  wire        immi_enable,
    input  wire        inc,         // currently unused; kept for parity
    input  wire        jmp,
    output reg  [15:0] result,
    output reg         branch
);

    /* verilator lint_off UNUSED */
    wire _unused_inc = inc;
    /* verilator lint_on UNUSED */

    always @(*) begin
        // Defaults
        result = 16'h0000;
        branch = 1'b0;

        if (immi_enable) begin
            case (alu_op)
                4'b0000: result = b + c;                       // ADDI / LW / SW
                4'b0001: if (a == b) begin                     // BEQ
                            result = pc_out + c;
                            branch = 1'b1;
                         end
                4'b0010: if (a != b) begin                     // BNE
                            result = pc_out + c;
                            branch = 1'b1;
                         end
                default: result = 16'h0000;
            endcase
        end
        else begin
            case (alu_op)
                4'b0000: result = a + b;                       // ADD
                4'b0001: result = a - b;                       // SUB
                4'b0010: result = a << b[3:0];                 // SLL
                4'b0011: result = a & b;                       // AND
                default: result = 16'h0000;
            endcase
        end

        // JMP override: target = PC + sign_extend(jmp_diff)
        if (jmp) begin
            result = pc_out + jmp_diff;
        end
    end

endmodule
