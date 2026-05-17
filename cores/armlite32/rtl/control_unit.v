// =============================================================================
// control_unit.v  --  armlite32 decoder
// =============================================================================
// Looks at instruction[27:25] ("type") to dispatch into:
//   - Data processing (register or immediate Op2)
//   - Load / store
//   - Branch / Branch-with-Link
// Then emits the per-instruction control signals.
//
// The cond_unit elsewhere decides whether to actually let the instruction
// retire; the control unit just produces the *would-be* signals.
// =============================================================================
`timescale 1ns / 1ps

`include "defines.v"

module control_unit (
    input  wire [31:0] instruction,
    output reg         is_dp_imm,
    output reg         is_dp_reg,
    output reg         is_load,
    output reg         is_store,
    output reg         is_branch,
    output reg         is_branch_link,
    output reg  [3:0]  dp_opcode,
    output reg         dp_writeback,    // 0 for TST/TEQ/CMP/CMN
    output reg         set_flags,       // S bit (or always for compare ops)
    output reg         use_pre_index,   // P bit  (load/store)
    output reg         add_offset,      // U bit  (load/store)  1 = +offset
    output reg         ls_writeback     // W bit
);

    wire [2:0] type_field = instruction[27:25];
    wire [3:0] opcode     = instruction[24:21];
    wire       s_bit      = instruction[20];

    // load/store sub-fields
    wire p_bit = instruction[24];
    wire u_bit = instruction[23];
    wire w_bit = instruction[21];
    wire l_bit = instruction[20];

    always @(*) begin
        // Defaults: NOP-like.
        is_dp_imm       = 1'b0;
        is_dp_reg       = 1'b0;
        is_load         = 1'b0;
        is_store        = 1'b0;
        is_branch       = 1'b0;
        is_branch_link  = 1'b0;
        dp_opcode       = 4'h0;
        dp_writeback    = 1'b0;
        set_flags       = 1'b0;
        use_pre_index   = 1'b0;
        add_offset      = 1'b1;
        ls_writeback    = 1'b0;

        case (type_field)
            `TYPE_DP_REG: begin
                is_dp_reg    = 1'b1;
                dp_opcode    = opcode;
                set_flags    = s_bit | (opcode == `DP_TST) | (opcode == `DP_TEQ)
                                     | (opcode == `DP_CMP) | (opcode == `DP_CMN);
                dp_writeback = (opcode != `DP_TST) && (opcode != `DP_TEQ)
                            && (opcode != `DP_CMP) && (opcode != `DP_CMN);
            end
            `TYPE_DP_IMM: begin
                is_dp_imm    = 1'b1;
                dp_opcode    = opcode;
                set_flags    = s_bit | (opcode == `DP_TST) | (opcode == `DP_TEQ)
                                     | (opcode == `DP_CMP) | (opcode == `DP_CMN);
                dp_writeback = (opcode != `DP_TST) && (opcode != `DP_TEQ)
                            && (opcode != `DP_CMP) && (opcode != `DP_CMN);
            end
            `TYPE_LS_IMM: begin
                is_load       = l_bit;
                is_store      = ~l_bit;
                use_pre_index = p_bit;
                add_offset    = u_bit;
                ls_writeback  = w_bit;
            end
            `TYPE_BR: begin
                is_branch      = 1'b1;
                is_branch_link = instruction[24];   // L bit
            end
            default: ;
        endcase
    end

endmodule
