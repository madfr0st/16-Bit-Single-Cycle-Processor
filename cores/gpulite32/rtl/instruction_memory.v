// =============================================================================
// instruction_memory.v  --  32-bit ROM for gpulite32 (word-addressed)
// =============================================================================
// DEMO PROGRAM (each of the 8 lanes runs the SAME instruction stream, but
// reads its OWN %tid.x and writes to its OWN slot in global memory):
//
//   // Each thread computes  out[tid] = tid * tid;
//   PC=0x00  S2R   R0, %tid.x        ; R0[lane] = lane id          (0..7)
//   PC=0x04  MUL   R1, R0, R0         ; R1[lane] = tid * tid       (0,1,4,9,16,25,36,49)
//   PC=0x08  SHL   R2, R0, #2         ; R2[lane] = tid * 4          (byte offset)
//   PC=0x0C  ST.G  [R2 + 0], R1       ; GLOBAL[tid*4] = R1[lane]
//   PC=0x10  EXIT
// =============================================================================
`timescale 1ns / 1ps

`include "defines.v"

module instruction_memory #(
    parameter DEPTH_WORDS = 1024
) (
    input  wire [31:0] address,
    output reg  [31:0] instruction
);

    reg [31:0] mem [0:DEPTH_WORDS-1];
    integer    i;

    // ---- Hand-assembly helpers --------------------------------------------
    // Format: { opcode[4:0], not_p[0], pi[2:0], dst[3:0], src1[3:0], src2[3:0], imm11[10:0] }
    function [31:0] ENC (
        input [4:0] op,
        input       np,
        input [2:0] pi,
        input [3:0] dst,
        input [3:0] s1,
        input [3:0] s2,
        input [10:0] imm);
        ENC = {op, np, pi, dst, s1, s2, imm};
    endfunction

    initial begin
        for (i = 0; i < DEPTH_WORDS; i = i + 1) mem[i] = 32'h0;

`ifdef MEM_HEX_FILE
        $readmemh(`MEM_HEX_FILE, mem);
`else
        // PC=0x00  S2R    R0, %tid.x         (always, lane 0..7 -> R0=0..7)
        mem[0] = ENC(`OP_S2R_TID, 1'b0, `PRED_ALWAYS, 4'd0, 4'd0, 4'd0, 11'd0);
        // PC=0x04  MUL    R1, R0, R0         (R1[lane] = tid * tid)
        mem[1] = ENC(`OP_MUL,     1'b0, `PRED_ALWAYS, 4'd1, 4'd0, 4'd0, 11'd0);
        // PC=0x08  MOV    R3, #2             (shift count for 4-byte stride)
        mem[2] = ENC(`OP_MOV_RI,  1'b0, `PRED_ALWAYS, 4'd3, 4'd0, 4'd0, 11'd2);
        // PC=0x0C  SHL    R2, R0, R3         (R2[lane] = tid * 4 = byte offset)
        mem[3] = ENC(`OP_SHL,     1'b0, `PRED_ALWAYS, 4'd2, 4'd0, 4'd3, 11'd0);
        // PC=0x10  ST.G   [R2 + 0], R1       (GLOBAL[tid*4] = tid*tid)
        mem[4] = ENC(`OP_ST_G,    1'b0, `PRED_ALWAYS, 4'd1, 4'd2, 4'd0, 11'd0);
        // PC=0x14  EXIT                      (BAR_EXIT with imm[10]=1)
        mem[5] = ENC(`OP_BAR_EXIT,1'b0, `PRED_ALWAYS, 4'd0, 4'd0, 4'd0, 11'h400);
`endif
    end

    always @(*) begin
        instruction = mem[address[31:2]];
    end

endmodule
