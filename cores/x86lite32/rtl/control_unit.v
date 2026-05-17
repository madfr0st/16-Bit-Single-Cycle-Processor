// =============================================================================
// control_unit.v  --  x86lite32 opcode -> control signal decoder
// =============================================================================
// Single combinational cone. Every signal is assigned in every arm to prevent
// latch inference. Conditional-branch evaluation is split out so the PC unit
// can mux on the decoded `branch_taken` signal in the same cycle.
//
// Categories (see defines.v for opcode encodings):
//   * MOV_RR / MOV_RI / LD / ST            data movement
//   * ADD/SUB/AND/OR/XOR/CMP/...           arithmetic + logical (set flags)
//   * SHL/SHR/SAR                          shifts (set flags)
//   * INC/DEC/NEG/NOT                      unary
//   * PUSH/POP/CALL/RET                    stack
//   * JMP/JE/JNE/JG/JL/JGE/JLE             control flow
//   * HLT                                  halt
//
// Control signals exported:
//   alu_op           ALU operation
//   alu_b_imm        ALU operand-B mux: 0 -> src register, 1 -> sign-extended imm
//   alu_a_zero       ALU operand-A force: 1 -> A=0 (for MOV_RI: A=0, B=imm)
//   reg_we           write-back into dst from ALU result
//   reg_wb_mem       writeback uses memory output (LD, POP)
//   mem_re / mem_we  data memory enables
//   mem_addr_sel     0 -> alu_result; 1 -> ESP   (PUSH/POP/CALL/RET)
//   mem_wdata_sel    0 -> dst register; 1 -> PC+4 (CALL pushes return address)
//   flags_update     latch new flags on next clock edge
//   esp_delta        -4 / 0 / +4 for PUSH/CALL / (everything else) / POP/RET
//   esp_we           commit esp_delta to R15 at next edge
//   is_jump          unconditional branch (JMP, CALL)
//   is_cond_jump     conditional branch (J*)  -> control unit emits cond_code
//   cond_code[3:0]   which condition predicate to evaluate
//   is_ret           pop PC from stack
//   halt             freeze PC
// =============================================================================
`timescale 1ns / 1ps

`include "defines.v"

module control_unit (
    input  wire [31:0] instruction,
    output reg  [3:0]  alu_op,
    output reg         alu_b_imm,
    output reg         alu_a_zero,
    output reg         alu_a_src,        // 1 -> ALU A = src (for LD/ST addr); 0 -> A = dst
    output reg         reg_we,
    output reg         reg_wb_mem,
    output reg         mem_re,
    output reg         mem_we,
    output reg         mem_addr_sel,
    output reg         mem_wdata_sel,
    output reg         flags_update,
    output reg signed [31:0] esp_delta,
    output reg         esp_we,
    output reg         is_jump,
    output reg         is_cond_jump,
    output reg  [3:0]  cond_code,
    output reg         is_ret,
    output reg         halt
);

    wire [7:0] opcode = instruction[31:24];

    always @(*) begin
        // ---- Safe defaults (NOP-like) --------------------------------------
        alu_op        = `ALU_PASS_B;
        alu_b_imm     = 1'b0;
        alu_a_zero    = 1'b0;
        alu_a_src     = 1'b0;
        reg_we        = 1'b0;
        reg_wb_mem    = 1'b0;
        mem_re        = 1'b0;
        mem_we        = 1'b0;
        mem_addr_sel  = 1'b0;
        mem_wdata_sel = 1'b0;
        flags_update  = 1'b0;
        esp_delta     = 32'sd0;
        esp_we        = 1'b0;
        is_jump       = 1'b0;
        is_cond_jump  = 1'b0;
        cond_code     = 4'h0;
        is_ret        = 1'b0;
        halt          = 1'b0;

        case (opcode)
            // ---------------- Data movement --------------------------------
            `OP_MOV_RR: begin
                alu_op = `ALU_PASS_B;
                reg_we = 1'b1;
            end
            `OP_MOV_RI: begin
                alu_op     = `ALU_PASS_B;
                alu_b_imm  = 1'b1;
                reg_we     = 1'b1;
            end
            `OP_LD: begin
                alu_op     = `ALU_ADD;
                alu_a_src  = 1'b1;          // addr = src + imm
                alu_b_imm  = 1'b1;
                mem_re     = 1'b1;
                reg_we     = 1'b1;
                reg_wb_mem = 1'b1;
            end
            `OP_ST: begin
                alu_op    = `ALU_ADD;
                alu_a_src = 1'b1;           // addr = src + imm
                alu_b_imm = 1'b1;
                mem_we    = 1'b1;
                // mem_wdata_sel=0 -> stores dst register through to memory
            end

            // ---------------- Arithmetic / logical -------------------------
            `OP_ADD: begin alu_op=`ALU_ADD; reg_we=1; flags_update=1; end
            `OP_SUB: begin alu_op=`ALU_SUB; reg_we=1; flags_update=1; end
            `OP_AND: begin alu_op=`ALU_AND; reg_we=1; flags_update=1; end
            `OP_OR : begin alu_op=`ALU_OR ; reg_we=1; flags_update=1; end
            `OP_XOR: begin alu_op=`ALU_XOR; reg_we=1; flags_update=1; end
            `OP_CMP: begin alu_op=`ALU_SUB; reg_we=0; flags_update=1; end

            `OP_ADDI: begin alu_op=`ALU_ADD; alu_b_imm=1; reg_we=1; flags_update=1; end
            `OP_SUBI: begin alu_op=`ALU_SUB; alu_b_imm=1; reg_we=1; flags_update=1; end
            `OP_CMPI: begin alu_op=`ALU_SUB; alu_b_imm=1; reg_we=0; flags_update=1; end

            // ---------------- Shifts ---------------------------------------
            `OP_SHL: begin alu_op=`ALU_SHL; reg_we=1; flags_update=1; end
            `OP_SHR: begin alu_op=`ALU_SHR; reg_we=1; flags_update=1; end
            `OP_SAR: begin alu_op=`ALU_SAR; reg_we=1; flags_update=1; end

            // ---------------- Unary ----------------------------------------
            // For INC/DEC we use ADD/SUB with B forced to the immediate +-1
            // via alu_b_imm=1 and an imm of 0x0001 generated in cpu.v from
            // the unary-instruction itself. To keep the decoder simple we
            // route through a dedicated combinational override; see cpu.v.
            `OP_INC: begin alu_op=`ALU_ADD; alu_b_imm=1; reg_we=1; flags_update=1; end
            `OP_DEC: begin alu_op=`ALU_SUB; alu_b_imm=1; reg_we=1; flags_update=1; end
            `OP_NEG: begin alu_op=`ALU_NEG; reg_we=1; flags_update=1; end
            `OP_NOT: begin alu_op=`ALU_NOT; reg_we=1; flags_update=0; end

            // ---------------- Stack ----------------------------------------
            // PUSH:  ESP -= 4; MEM[ESP] <- dst
            `OP_PUSH: begin
                mem_addr_sel = 1'b1;
                mem_we       = 1'b1;
                esp_delta    = -32'sd4;
                esp_we       = 1'b1;
            end
            // POP:   dst <- MEM[ESP]; ESP += 4
            `OP_POP: begin
                mem_addr_sel = 1'b1;
                mem_re       = 1'b1;
                reg_we       = 1'b1;
                reg_wb_mem   = 1'b1;
                esp_delta    = 32'sd4;
                esp_we       = 1'b1;
            end
            // CALL: ESP -= 4; MEM[ESP] <- PC+4; PC <- PC + sext(imm)
            `OP_CALL: begin
                mem_addr_sel  = 1'b1;
                mem_we        = 1'b1;
                mem_wdata_sel = 1'b1;          // store return address
                esp_delta     = -32'sd4;
                esp_we        = 1'b1;
                is_jump       = 1'b1;
            end
            // RET:  PC <- MEM[ESP]; ESP += 4
            `OP_RET: begin
                mem_addr_sel = 1'b1;
                mem_re       = 1'b1;
                esp_delta    = 32'sd4;
                esp_we       = 1'b1;
                is_ret       = 1'b1;
            end

            // ---------------- Control flow ---------------------------------
            `OP_JMP: begin is_jump = 1'b1; end
            `OP_JE:  begin is_cond_jump = 1'b1; cond_code = 4'h0; end
            `OP_JNE: begin is_cond_jump = 1'b1; cond_code = 4'h1; end
            `OP_JG:  begin is_cond_jump = 1'b1; cond_code = 4'h2; end
            `OP_JL:  begin is_cond_jump = 1'b1; cond_code = 4'h3; end
            `OP_JGE: begin is_cond_jump = 1'b1; cond_code = 4'h4; end
            `OP_JLE: begin is_cond_jump = 1'b1; cond_code = 4'h5; end

            `OP_HLT: begin halt = 1'b1; end

            default: ;   // covered by defaults
        endcase
    end

endmodule
