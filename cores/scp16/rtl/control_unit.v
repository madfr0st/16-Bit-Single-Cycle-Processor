// =============================================================================
// control_unit.v  --  combinational opcode -> control signal decoder
// =============================================================================
// One-hot-ish decoder. There are no microcode roms here: a single-cycle CPU
// can finish its control logic in pure combinational gates because each
// instruction completes in one cycle.
//
// OPCODE MAP  (instruction[15:12])
//   0000  R-type   : ADD / SUB / SLL / AND   (funct = instruction[3:0])
//   0001  I-type   : LW    rd, [rs + imm]
//   0010  I-type   : SW    rd, [rs + imm]
//   0011  I-type   : ADDI  rd, rs, imm
//   0100  I-type   : BEQ   if (rd == rs) PC = PC + imm
//   0101  I-type   : BNE   if (rd != rs) PC = PC + imm
//   0110  J-type   : JMP   PC = PC + sext(jmp_diff)
//
// CONTROL SIGNAL MEANINGS
//   alu_op[3:0]  : ALU operation selector  (see rtl/alu.v)
//   reg_write    : 1 -> write Rd at next clock edge
//   mem_read     : 1 -> data_memory drives mem_out
//   mem_write    : 1 -> data_memory latches data_in on clock edge
//   mux_sel      : writeback mux. 0 -> ALU result, 1 -> mem_out
//   byte_enable  : 1 -> 8-bit memory access, 0 -> 16-bit memory access
//   immi_enable  : 1 -> ALU B operand is sign-extended imm (I-type / branch)
//   jmp          : 1 -> next PC is jump target
//
// EVERY signal is assigned in EVERY arm of the case statement (including
// default) to guarantee no inferred latches.
// =============================================================================
`timescale 1ns / 1ps

module control_unit (
    input  wire [15:0] instruction,
    output reg  [3:0]  alu_op,
    output reg         reg_write,
    output reg         mem_read,
    output reg         mem_write,
    output reg         mux_sel,
    output reg         byte_enable,
    output reg         immi_enable,
    output reg         jmp
);

    always @(*) begin
        // Safe defaults: NOP-like (no writes, no jump, no memory).
        alu_op      = 4'b0000;
        reg_write   = 1'b0;
        mem_read    = 1'b0;
        mem_write   = 1'b0;
        mux_sel     = 1'b0;
        byte_enable = 1'b0;
        immi_enable = 1'b0;
        jmp         = 1'b0;

        case (instruction[15:12])
            // ----- R-type ----------------------------------------------------
            4'b0000: begin
                case (instruction[3:0])
                    4'b0000: alu_op = 4'b0000;  // ADD
                    4'b0001: alu_op = 4'b0001;  // SUB
                    4'b0010: alu_op = 4'b0010;  // SLL
                    4'b0011: alu_op = 4'b0011;  // AND
                    default: alu_op = 4'b0000;
                endcase
                reg_write   = 1'b1;
            end

            // ----- LW : rd <- MEM[rs + imm] ----------------------------------
            4'b0001: begin
                alu_op      = 4'b0000;  // ALU computes effective addr (B + C)
                reg_write   = 1'b1;
                mem_read    = 1'b1;
                mux_sel     = 1'b1;     // writeback from memory
                immi_enable = 1'b1;
            end

            // ----- SW : MEM[rs + imm] <- rd ----------------------------------
            4'b0010: begin
                alu_op      = 4'b0000;
                mem_write   = 1'b1;
                immi_enable = 1'b1;
            end

            // ----- ADDI : rd <- rs + sext(imm) -------------------------------
            4'b0011: begin
                alu_op      = 4'b0000;
                reg_write   = 1'b1;
                immi_enable = 1'b1;
            end

            // ----- BEQ : if (rd == rs) PC <- PC + sext(imm) ------------------
            4'b0100: begin
                alu_op      = 4'b0001;  // BEQ in ALU
                immi_enable = 1'b1;
            end

            // ----- BNE : if (rd != rs) PC <- PC + sext(imm) ------------------
            4'b0101: begin
                alu_op      = 4'b0010;  // BNE in ALU
                immi_enable = 1'b1;
            end

            // ----- JMP : PC <- PC + sext(jmp_diff) ---------------------------
            4'b0110: begin
                jmp         = 1'b1;
            end

            default: ;  // already covered by safe defaults
        endcase
    end

endmodule
