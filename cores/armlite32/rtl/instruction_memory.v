// =============================================================================
// instruction_memory.v  --  32-bit ROM for armlite32 (word addressed via PC[31:2])
// =============================================================================
// Demo program: a small loop that sums 1..10 into R2, then halts via an
// always-taken self-branch (the "infinite loop end").
//
//   MOV  R1, #1                    ; counter
//   MOV  R2, #0                    ; accumulator
//   MOV  R3, #10                   ; limit
// loop:
//   ADD  R2, R2, R1
//   ADD  R1, R1, #1
//   CMP  R1, R3
//   BLE  loop                      ; while (R1 <= R3)
// end:
//   B    end                       ; infinite loop -> "halt"
//
// All instructions use COND_AL (always) except BLE, which uses COND_LE.
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

    // ---- Helpers to hand-assemble ARM-style words --------------------------
    // Data-processing immediate (I=1):  cond,001,opcode,S,Rn,Rd,rot,imm8
    function [31:0] DP_IMM (
        input [3:0] cond, input [3:0] opcode, input s,
        input [3:0] rn, input [3:0] rd,
        input [3:0] rot, input [7:0] imm8);
        DP_IMM = {cond, `TYPE_DP_IMM, opcode, s, rn, rd, rot, imm8};
    endfunction

    // Data-processing register (I=0): cond,000,opcode,S,Rn,Rd,shamt,sh,0,Rm
    function [31:0] DP_REG (
        input [3:0] cond, input [3:0] opcode, input s,
        input [3:0] rn, input [3:0] rd,
        input [4:0] shamt, input [1:0] sh, input [3:0] rm);
        DP_REG = {cond, `TYPE_DP_REG, opcode, s, rn, rd, shamt, sh, 1'b0, rm};
    endfunction

    // Branch:  cond,101,L,signed_imm24
    function [31:0] BR (
        input [3:0] cond, input l, input [23:0] imm24);
        BR = {cond, `TYPE_BR, l, imm24};
    endfunction

    initial begin
        for (i = 0; i < DEPTH_WORDS; i = i + 1) mem[i] = 32'h0;

`ifdef MEM_HEX_FILE
        $readmemh(`MEM_HEX_FILE, mem);
`else
        // PC=0x00  MOV R1, #1
        mem[0] = DP_IMM(`COND_AL, `DP_MOV, 1'b0, 4'd0, 4'd1, 4'd0, 8'd1);

        // PC=0x04  MOV R2, #0
        mem[1] = DP_IMM(`COND_AL, `DP_MOV, 1'b0, 4'd0, 4'd2, 4'd0, 8'd0);

        // PC=0x08  MOV R3, #10
        mem[2] = DP_IMM(`COND_AL, `DP_MOV, 1'b0, 4'd0, 4'd3, 4'd0, 8'd10);

        // PC=0x0C  ADD R2, R2, R1
        mem[3] = DP_REG(`COND_AL, `DP_ADD, 1'b0, 4'd2, 4'd2, 5'd0, `SH_LSL, 4'd1);

        // PC=0x10  ADD R1, R1, #1
        mem[4] = DP_IMM(`COND_AL, `DP_ADD, 1'b0, 4'd1, 4'd1, 4'd0, 8'd1);

        // PC=0x14  CMP R1, R3
        mem[5] = DP_REG(`COND_AL, `DP_CMP, 1'b1, 4'd1, 4'd0, 5'd0, `SH_LSL, 4'd3);

        // PC=0x18  BLE  loop   -- loop is at PC=0x0C, offset = (0x0C - (0x18+8))/4 = -5
        //                        24-bit signed:  -5 = 0xFFFFFB
        mem[6] = BR(`COND_LE, 1'b0, 24'hFFFFFB);

        // PC=0x1C  B end       -- end is at PC=0x1C, offset = (0x1C - (0x1C+8))/4 = -2 = 0xFFFFFE
        mem[7] = BR(`COND_AL, 1'b0, 24'hFFFFFE);
`endif
    end

    always @(*) begin
        instruction = mem[address[31:2]];
    end

endmodule
