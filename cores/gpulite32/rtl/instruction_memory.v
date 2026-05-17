// =============================================================================
// instruction_memory.v  --  32-bit ROM for gpulite32 (word-addressed)
// =============================================================================
// PAINT-SOFTWARE DEMO KERNEL
// --------------------------
// Treats the first 256 bytes of global memory as an 8x8 framebuffer
//     pixel(row, col)  lives at GLOBAL[(row*8 + col) * 4]
// and demonstrates three classic paint-software primitives, run in parallel
// across the 8 SIMT lanes:
//
//   PRIMITIVE 1  --  clear_canvas(color=0)
//       Each lane loops over rows 0..7 and writes 0 into its own column.
//       8 lanes x 8 rows = 64 pixels cleared in 8 loop iterations.
//
//   PRIMITIVE 2  --  draw_hline(row=3, color=170)
//       One ST in parallel: lane i writes color=170 to pixel (3, i).
//       64 pixels' worth of work done in ONE cycle.  This is the magic of SIMT.
//
//   PRIMITIVE 3  --  plot_pixel(5, 5, color=255)
//       Predicate gates the store so only lane 5 retires the write.
//       Other lanes still flow through the instruction (the cost of SIMT
//       divergence) but their writes are squashed.
//
// FINAL CANVAS (1 = lit, . = clear)
//
//     . . . . . . . .       row 0
//     . . . . . . . .       row 1
//     . . . . . . . .       row 2
//     1 1 1 1 1 1 1 1       row 3   <-- hline
//     . . . . . . . .       row 4
//     . . . . . 1 . .       row 5   <-- single pixel at (5,5)
//     . . . . . . . .       row 6
//     . . . . . . . .       row 7
//
// REGISTER USAGE (per lane)
//   R0  = tid          (= column index for this lane)
//   R1  = scratch (pixel color in flight)
//   R2  = scratch (byte address in flight)
//   R3  = constant 5  (used for vertical placement of the dot)
//   R5  = row counter / row literal
//   R6  = scratch     (row literal 5 for the dot)
//   R8  = constant 8  (loop limit)
//   R10 = constant 1  (loop increment)
//   R11 = constant 2  (word->byte shift  =  *4)
//   R12 = constant 3  (col->stride shift =  *8)
//   P0  = (row >= 8)?    loop-exit predicate
//   P1  = (col == 5)?    single-lane plot predicate
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
        // ---- Setup: hoist loop constants ------------------------------------
        // PC=0x00  MOV R10, #1
        mem[ 0] = ENC(`OP_MOV_RI,   1'b0, `PRED_ALWAYS, 4'd10, 4'd0,  4'd0,  11'd1);
        // PC=0x04  MOV R11, #2      (word -> byte shift)
        mem[ 1] = ENC(`OP_MOV_RI,   1'b0, `PRED_ALWAYS, 4'd11, 4'd0,  4'd0,  11'd2);
        // PC=0x08  MOV R12, #3      (col -> stride-of-8 shift)
        mem[ 2] = ENC(`OP_MOV_RI,   1'b0, `PRED_ALWAYS, 4'd12, 4'd0,  4'd0,  11'd3);
        // PC=0x0C  MOV R8, #8       (loop limit)
        mem[ 3] = ENC(`OP_MOV_RI,   1'b0, `PRED_ALWAYS, 4'd8,  4'd0,  4'd0,  11'd8);
        // PC=0x10  S2R R0, %tid.x   (R0 = column for this lane)
        mem[ 4] = ENC(`OP_S2R_TID,  1'b0, `PRED_ALWAYS, 4'd0,  4'd0,  4'd0,  11'd0);

        // ---- PRIMITIVE 1: clear_canvas(0) -----------------------------------
        // PC=0x14  MOV R5, #0       (row = 0)
        mem[ 5] = ENC(`OP_MOV_RI,   1'b0, `PRED_ALWAYS, 4'd5,  4'd0,  4'd0,  11'd0);

        // clear_loop:    word idx 6  (byte 0x18)
        // PC=0x18  SETP.GE P0, R5, R8
        mem[ 6] = ENC(`OP_SETP_GE,  1'b0, `PRED_ALWAYS, 4'd0,  4'd5,  4'd8,  11'd0);
        // PC=0x1C  @P0 BRA after_clear   (target word 15 -> imm = 15-7-1 = 7)
        mem[ 7] = ENC(`OP_BRA,      1'b0, 3'b000,       4'd0,  4'd0,  4'd0,  11'd7);
        // PC=0x20  SHL R2, R5, R12  (R2 = row * 8)
        mem[ 8] = ENC(`OP_SHL,      1'b0, `PRED_ALWAYS, 4'd2,  4'd5,  4'd12, 11'd0);
        // PC=0x24  ADD R2, R2, R0   (R2 = row*8 + col)
        mem[ 9] = ENC(`OP_ADD,      1'b0, `PRED_ALWAYS, 4'd2,  4'd2,  4'd0,  11'd0);
        // PC=0x28  SHL R2, R2, R11  (R2 = (row*8+col) * 4 = byte addr)
        mem[10] = ENC(`OP_SHL,      1'b0, `PRED_ALWAYS, 4'd2,  4'd2,  4'd11, 11'd0);
        // PC=0x2C  MOV R1, #0       (clear color)
        mem[11] = ENC(`OP_MOV_RI,   1'b0, `PRED_ALWAYS, 4'd1,  4'd0,  4'd0,  11'd0);
        // PC=0x30  ST.G [R2+0], R1
        mem[12] = ENC(`OP_ST_G,     1'b0, `PRED_ALWAYS, 4'd1,  4'd2,  4'd0,  11'd0);
        // PC=0x34  ADD R5, R5, R10  (row++)
        mem[13] = ENC(`OP_ADD,      1'b0, `PRED_ALWAYS, 4'd5,  4'd5,  4'd10, 11'd0);
        // PC=0x38  BRA clear_loop   (back to word 6 -> imm = 6-14-1 = -9 = 0x7F7)
        mem[14] = ENC(`OP_BRA,      1'b0, `PRED_ALWAYS, 4'd0,  4'd0,  4'd0,  11'h7F7);

        // ---- PRIMITIVE 2: draw_hline(row=3, color=170) ----------------------
        // after_clear:   word idx 15
        // PC=0x3C  MOV R5, #3
        mem[15] = ENC(`OP_MOV_RI,   1'b0, `PRED_ALWAYS, 4'd5,  4'd0,  4'd0,  11'd3);
        // PC=0x40  SHL R2, R5, R12
        mem[16] = ENC(`OP_SHL,      1'b0, `PRED_ALWAYS, 4'd2,  4'd5,  4'd12, 11'd0);
        // PC=0x44  ADD R2, R2, R0
        mem[17] = ENC(`OP_ADD,      1'b0, `PRED_ALWAYS, 4'd2,  4'd2,  4'd0,  11'd0);
        // PC=0x48  SHL R2, R2, R11
        mem[18] = ENC(`OP_SHL,      1'b0, `PRED_ALWAYS, 4'd2,  4'd2,  4'd11, 11'd0);
        // PC=0x4C  MOV R1, #170     (mid-grey color = 0xAA)
        mem[19] = ENC(`OP_MOV_RI,   1'b0, `PRED_ALWAYS, 4'd1,  4'd0,  4'd0,  11'd170);
        // PC=0x50  ST.G [R2+0], R1   <- 8 lanes write 8 pixels in ONE cycle
        mem[20] = ENC(`OP_ST_G,     1'b0, `PRED_ALWAYS, 4'd1,  4'd2,  4'd0,  11'd0);

        // ---- PRIMITIVE 3: plot_pixel(5, 5, 255) -----------------------------
        // PC=0x54  MOV R3, #5       (column to test)
        mem[21] = ENC(`OP_MOV_RI,   1'b0, `PRED_ALWAYS, 4'd3,  4'd0,  4'd0,  11'd5);
        // PC=0x58  SETP.EQ P1, R0, R3   (P1 = (col == 5))
        mem[22] = ENC(`OP_SETP_EQ,  1'b0, `PRED_ALWAYS, 4'd0,  4'd0,  4'd3,  11'd1);
        // PC=0x5C  MOV R6, #5       (row)
        mem[23] = ENC(`OP_MOV_RI,   1'b0, `PRED_ALWAYS, 4'd6,  4'd0,  4'd0,  11'd5);
        // PC=0x60  SHL R2, R6, R12  (row * 8)
        mem[24] = ENC(`OP_SHL,      1'b0, `PRED_ALWAYS, 4'd2,  4'd6,  4'd12, 11'd0);
        // PC=0x64  ADD R2, R2, R3   (row*8 + 5)
        mem[25] = ENC(`OP_ADD,      1'b0, `PRED_ALWAYS, 4'd2,  4'd2,  4'd3,  11'd0);
        // PC=0x68  SHL R2, R2, R11  (* 4 = byte addr)
        mem[26] = ENC(`OP_SHL,      1'b0, `PRED_ALWAYS, 4'd2,  4'd2,  4'd11, 11'd0);
        // PC=0x6C  MOV R1, #255     (bright color)
        mem[27] = ENC(`OP_MOV_RI,   1'b0, `PRED_ALWAYS, 4'd1,  4'd0,  4'd0,  11'd255);
        // PC=0x70  @P1 ST.G [R2+0], R1   <- only lane 5 actually writes
        mem[28] = ENC(`OP_ST_G,     1'b0, 3'b001,       4'd1,  4'd2,  4'd0,  11'd0);

        // ---- Done ----------------------------------------------------------
        // PC=0x74  EXIT
        mem[29] = ENC(`OP_BAR_EXIT, 1'b0, `PRED_ALWAYS, 4'd0,  4'd0,  4'd0,  11'h400);
`endif
    end

    always @(*) begin
        instruction = mem[address[31:2]];
    end

endmodule
