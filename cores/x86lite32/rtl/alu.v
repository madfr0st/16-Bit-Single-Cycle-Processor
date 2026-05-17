// =============================================================================
// alu.v  --  32-bit ALU + flag generator for x86lite32
// =============================================================================
// Produces:
//   result         -- 32-bit ALU output
//   flags_next     -- {OF, SF, ZF, CF} computed from the operation
//
// Flag rules (x86-style):
//   CF  = unsigned carry-out  (ADD)  OR  unsigned borrow  (SUB)
//   ZF  = (result == 0)
//   SF  = result[31]
//   OF  = signed overflow: ADD  -> (a[31]==b[31]) && (result[31]!=a[31])
//                          SUB  -> (a[31]!=b[31]) && (result[31]!=a[31])
//   Logical ops (AND/OR/XOR/SHL/SHR/SAR/NOT/PASS) clear CF and OF, update SF/ZF.
//   NEG = (0 - a), so flags follow SUB rules with a=0, b=operand.
// =============================================================================
`timescale 1ns / 1ps

`include "defines.v"

module alu (
    input  wire [31:0] a,          // first operand  (typically dst)
    input  wire [31:0] b,          // second operand (typically src or imm)
    input  wire [3:0]  op,         // ALU_* selector
    output reg  [31:0] result,
    output reg  [3:0]  flags_next  // {OF, SF, ZF, CF}
);

    reg [32:0] add_ext;
    reg [32:0] sub_ext;
    reg        cf, zf, sf, of;

    always @(*) begin
        // -- precompute add/sub with carry bit visible -----------------------
        add_ext = {1'b0, a} + {1'b0, b};
        sub_ext = {1'b0, a} - {1'b0, b};

        // -- default flag computation (overridden per-op below) --------------
        cf = 1'b0;
        of = 1'b0;

        case (op)
            `ALU_ADD: begin
                result = add_ext[31:0];
                cf     = add_ext[32];
                of     = (a[31] == b[31]) && (result[31] != a[31]);
            end
            `ALU_SUB: begin
                result = sub_ext[31:0];
                cf     = sub_ext[32];                  // borrow indicator
                of     = (a[31] != b[31]) && (result[31] != a[31]);
            end
            `ALU_AND:    result = a & b;
            `ALU_OR:     result = a | b;
            `ALU_XOR:    result = a ^ b;
            `ALU_SHL:    result = a << b[4:0];
            `ALU_SHR:    result = a >> b[4:0];
            `ALU_SAR:    result = $signed(a) >>> b[4:0];
            `ALU_PASS_B: result = b;
            `ALU_NOT:    result = ~a;
            `ALU_NEG:    begin
                            result = 32'h0 - a;
                            cf     = (a != 32'h0);     // borrow if a != 0
                            of     = (a == 32'h8000_0000);
                         end
            default:     result = 32'h0;
        endcase

        zf = (result == 32'h0);
        sf = result[31];

        flags_next = {of, sf, zf, cf};
    end

endmodule
