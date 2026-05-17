// =============================================================================
// control_unit.v  --  gpulite32 opcode -> control signal decoder
// =============================================================================
// One combinational cone. The control signals fan out to all 8 lanes, plus
// drive the global structures (shared memory, global memory, warp PC).
//
// Compared to a CPU control unit the new wrinkle is the *predicate*: every
// instruction names a predicate register that GATES the per-lane writes.
// When a lane's predicate evaluates to false, the lane silently treats this
// cycle as a NOP for register / memory writes -- but the instruction still
// flowed through the pipeline. This is SIMT in a nutshell.
// =============================================================================
`timescale 1ns / 1ps

`include "defines.v"

module control_unit (
    input  wire [31:0] instruction,

    // ALU operation selector (re-uses opcode high bits semantically)
    output reg  [3:0]  alu_op,
    output reg         alu_b_imm,        // 1 -> ALU B = sext(imm); else src2

    // Register-file writeback
    output reg         reg_we,
    output reg         reg_wb_mem,       // 0 -> ALU result; 1 -> memory load

    // Special-source writeback
    output reg         reg_wb_tid,       // 1 -> writeback is the lane's tid.x
    output reg         reg_wb_ntid,      // 1 -> writeback is WARP_SIZE

    // Predicate-register writeback
    output reg         pred_we,
    output reg  [2:0]  pred_op,          // 0=EQ 1=NE 2=LT 3=LE 4=GT 5=GE

    // Memory subsystem
    output reg         mem_re,
    output reg         mem_we,
    output reg         is_shared,        // 0 -> global; 1 -> shared

    // Control flow / exit
    output reg         is_branch,
    output reg         is_exit
);

    wire [4:0] opcode = instruction[31:27];

    always @(*) begin
        // Defaults (NOP)
        alu_op       = 4'h0;
        alu_b_imm    = 1'b0;
        reg_we       = 1'b0;
        reg_wb_mem   = 1'b0;
        reg_wb_tid   = 1'b0;
        reg_wb_ntid  = 1'b0;
        pred_we      = 1'b0;
        pred_op      = 3'h0;
        mem_re       = 1'b0;
        mem_we       = 1'b0;
        is_shared    = 1'b0;
        is_branch    = 1'b0;
        is_exit      = 1'b0;

        case (opcode)
            // --- Data movement -----------------------------------------------
            `OP_MOV_RR:   begin reg_we = 1'b1; alu_op = 4'h0; alu_b_imm = 1'b0; end  // ALU PASS_B alternative: ADD with src1=0? simpler: just route mov path
            `OP_MOV_RI:   begin reg_we = 1'b1; alu_op = 4'h0; alu_b_imm = 1'b1; end  // dst <- 0 + sext(imm)
            `OP_S2R_TID:  begin reg_we = 1'b1; reg_wb_tid  = 1'b1; end
            `OP_S2R_NTID: begin reg_we = 1'b1; reg_wb_ntid = 1'b1; end

            // --- Arithmetic / logical ----------------------------------------
            `OP_ADD: begin reg_we=1; alu_op=4'h0; end
            `OP_SUB: begin reg_we=1; alu_op=4'h1; end
            `OP_MUL: begin reg_we=1; alu_op=4'h2; end
            `OP_AND: begin reg_we=1; alu_op=4'h3; end
            `OP_OR : begin reg_we=1; alu_op=4'h4; end
            `OP_XOR: begin reg_we=1; alu_op=4'h5; end
            `OP_SHL: begin reg_we=1; alu_op=4'h6; end
            `OP_SHR: begin reg_we=1; alu_op=4'h7; end

            `OP_ADDI: begin reg_we=1; alu_op=4'h0; alu_b_imm=1; end
            `OP_MULI: begin reg_we=1; alu_op=4'h2; alu_b_imm=1; end

            // --- SETP -- writes the predicate register, not the GPR ----------
            `OP_SETP_EQ: begin pred_we=1; pred_op=3'd0; end
            `OP_SETP_NE: begin pred_we=1; pred_op=3'd1; end
            `OP_SETP_LT: begin pred_we=1; pred_op=3'd2; end
            `OP_SETP_LE: begin pred_we=1; pred_op=3'd3; end
            `OP_SETP_GT: begin pred_we=1; pred_op=3'd4; end
            `OP_SETP_GE: begin pred_we=1; pred_op=3'd5; end

            // --- Memory  (effective addr = src1 + sext(imm)) -----------------
            `OP_LD_G: begin reg_we=1; reg_wb_mem=1; mem_re=1; alu_op=4'h0; alu_b_imm=1; end
            `OP_ST_G: begin                          mem_we=1; alu_op=4'h0; alu_b_imm=1; end
            `OP_LD_S: begin reg_we=1; reg_wb_mem=1; mem_re=1; is_shared=1; alu_op=4'h0; alu_b_imm=1; end
            `OP_ST_S: begin                          mem_we=1; is_shared=1; alu_op=4'h0; alu_b_imm=1; end

            // --- Control flow / sync / exit ---------------------------------
            `OP_BRA:      begin is_branch = 1'b1; end
            `OP_BAR_EXIT: begin is_exit   = instruction[10]; end
            default: ;
        endcase
    end

endmodule
