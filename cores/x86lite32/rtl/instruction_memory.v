// =============================================================================
// instruction_memory.v  --  32-bit word ROM for x86lite32
// =============================================================================
// Word-addressed for simplicity (each PC increment of +4 is +1 word).
// Returns a 32-bit instruction combinationally.
//
// Load a program by either:
//   * defining MEM_HEX_FILE at compile time   (preferred)
//   * editing the inline `initial` demo below
//
// DEMO PROGRAM
//   PC=0x00  MOV R1, #1            R1 = 1
//   PC=0x04  MOV R2, #0            R2 = 0
//   PC=0x08  ADD R2, R1            R2 += R1
//   PC=0x0C  ADD R1, R1            R1 += R1   (doubles)
//   PC=0x10  CMP R1, #128          flags = R1 - 128
//   PC=0x14  JL  -0x0C             back to PC=0x08 while R1 < 128
//   PC=0x18  HLT
// =============================================================================
`timescale 1ns / 1ps

`include "defines.v"

module instruction_memory #(
    parameter DEPTH_WORDS = 1024
) (
    input  wire [31:0] address,        // byte address; we use [31:2]
    output reg  [31:0] instruction
);

    reg [31:0] mem [0:DEPTH_WORDS-1];
    integer    i;

    initial begin
        for (i = 0; i < DEPTH_WORDS; i = i + 1) mem[i] = 32'h0000_0000;

`ifdef MEM_HEX_FILE
        $readmemh(`MEM_HEX_FILE, mem);
`else
        // {opcode, dst, src, imm16}
        //
        //   MOV R1, #1            01 1 0 0001
        mem[0] = {`OP_MOV_RI, 4'd1, 4'd0, 16'h0001};
        //   MOV R2, #0
        mem[1] = {`OP_MOV_RI, 4'd2, 4'd0, 16'h0000};
        //   ADD R2, R1
        mem[2] = {`OP_ADD,    4'd2, 4'd1, 16'h0000};
        //   ADD R1, R1
        mem[3] = {`OP_ADD,    4'd1, 4'd1, 16'h0000};
        //   CMP R1, #128
        mem[4] = {`OP_CMPI,   4'd1, 4'd0, 16'h0080};
        //   JL  -12     (back to PC=0x08, i.e. word 2)
        mem[5] = {`OP_JL,     4'd0, 4'd0, 16'hFFF4};   // -12 = 0xFFFFFFF4 trunc to 16 bits = 0xFFF4
        //   HLT
        mem[6] = {`OP_HLT,    4'd0, 4'd0, 16'h0000};
`endif
    end

    always @(*) begin
        instruction = mem[address[31:2]];
    end

endmodule
