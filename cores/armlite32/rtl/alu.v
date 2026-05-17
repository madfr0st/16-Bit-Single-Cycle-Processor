// =============================================================================
// alu.v  --  32-bit ALU + CPSR flag generator (ARM semantics)
// =============================================================================
// Operates on (a = Rn) and (b = Operand2).
// Flag bus packed as {N, Z, C, V}.
//
// Carry / borrow conventions (ARM specifies these *very* precisely):
//   ADD/ADC : C = unsigned carry out
//   SUB/SBC : C = NOT(unsigned borrow)    (so C=1 means no borrow)
//   RSB/RSC : same as SUB but with operands swapped
//   logical : C = preserved (forced to 0 here for simplicity; a real ARM
//             would set it from the shifter carry-out)
// =============================================================================
`timescale 1ns / 1ps

`include "defines.v"

module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  opcode,
    input  wire        cin,        // current CPSR C (for ADC/SBC/RSC)
    output reg  [31:0] result,
    output reg  [3:0]  flags_next  // {N, Z, C, V}
);

    reg [32:0] add_ext;
    reg [32:0] sub_ext;
    reg [32:0] rsb_ext;
    reg        nf, zf, cf, vf;
    reg        write_back;        // 1 -> result is meaningful; 0 -> TST/TEQ/CMP/CMN (flags only)

    always @(*) begin
        // -- precompute the common ops --------------------------------------
        add_ext = {1'b0, a} + {1'b0, b};
        sub_ext = {1'b0, a} - {1'b0, b};
        rsb_ext = {1'b0, b} - {1'b0, a};

        // defaults
        result     = 32'h0;
        cf         = 1'b0;
        vf         = 1'b0;
        write_back = 1'b1;

        case (opcode)
            `DP_AND: result = a & b;
            `DP_EOR: result = a ^ b;
            `DP_SUB: begin
                result = sub_ext[31:0];
                cf     = ~sub_ext[32];                 // C = NOT borrow
                vf     = (a[31] != b[31]) && (result[31] != a[31]);
            end
            `DP_RSB: begin
                result = rsb_ext[31:0];
                cf     = ~rsb_ext[32];
                vf     = (b[31] != a[31]) && (result[31] != b[31]);
            end
            `DP_ADD: begin
                result = add_ext[31:0];
                cf     = add_ext[32];
                vf     = (a[31] == b[31]) && (result[31] != a[31]);
            end
            `DP_ADC: begin
                {cf, result} = a + b + {31'b0, cin};
                vf           = (a[31] == b[31]) && (result[31] != a[31]);
            end
            `DP_SBC: begin
                {cf, result} = a - b - {31'b0, ~cin};
                cf           = ~cf;                    // borrow -> NOT C
                vf           = (a[31] != b[31]) && (result[31] != a[31]);
            end
            `DP_RSC: begin
                {cf, result} = b - a - {31'b0, ~cin};
                cf           = ~cf;
                vf           = (b[31] != a[31]) && (result[31] != b[31]);
            end
            `DP_TST: begin result = a & b; write_back = 1'b0; end
            `DP_TEQ: begin result = a ^ b; write_back = 1'b0; end
            `DP_CMP: begin
                result     = sub_ext[31:0]; write_back = 1'b0;
                cf         = ~sub_ext[32];
                vf         = (a[31] != b[31]) && (result[31] != a[31]);
            end
            `DP_CMN: begin
                result     = add_ext[31:0]; write_back = 1'b0;
                cf         = add_ext[32];
                vf         = (a[31] == b[31]) && (result[31] != a[31]);
            end
            `DP_ORR: result = a | b;
            `DP_MOV: result = b;
            `DP_BIC: result = a & (~b);
            `DP_MVN: result = ~b;
            default: result = 32'h0;
        endcase

        nf = result[31];
        zf = (result == 32'h0);

        flags_next = {nf, zf, cf, vf};
        /* verilator lint_off UNUSED */
        if (write_back) ; // keep write_back observable for future use
        /* verilator lint_on UNUSED */
    end

endmodule
