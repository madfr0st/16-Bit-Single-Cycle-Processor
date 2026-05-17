// =============================================================================
// instruction_memory.v  --  byte-addressed ROM, little-endian, async read
// =============================================================================
// The CPU asks for an instruction at byte-address `address`. Because each
// instruction is 16 bits, the returned word is { mem[address+1], mem[address] }
// (low byte at the lower address  =  little-endian).
//
// PROGRAM LOADING
//   1. Default: the inline `initial` block below loads a small demo program
//      (the same one the original project ran on the Basys 3).
//   2. Or define `MEM_HEX_FILE`  ->  load from a hex file via $readmemh.
//      In simulation:  vlog +define+MEM_HEX_FILE=\"program.hex\" ...
//
// DEMO PROGRAM
//   addr   bytes      mnemonic               effect
//   0x00:  11 31      ADDI R1, R1, 1         R1 = 1
//   0x02:  10 01      ADD  R1, R0, R1        R1 = R0 + R1 (= R1)
//   0x04:  10 01      ADD  R1, R0, R1
//   ...   (repeats so the LED visualization keeps moving)
//   0x12:  EE 6F      JMP  -0x112            wrap back to top of program
//
// Memory depth is 1024 bytes  ->  512 instructions; trivial to grow.
// =============================================================================
`timescale 1ns / 1ps

module instruction_memory #(
    parameter DEPTH_BYTES = 1024
) (
    input  wire [15:0]      address,
    output reg  [15:0]      instruction
);

    reg [7:0] mem [0:DEPTH_BYTES-1];
    integer   i;

    initial begin
        // Zero-initialize everything so unwritten addresses are deterministic
        for (i = 0; i < DEPTH_BYTES; i = i + 1) mem[i] = 8'h00;

`ifdef MEM_HEX_FILE
        $readmemh(`MEM_HEX_FILE, mem);
`else
        // ---- Inline demo program (preserved from the original Team 47 lab) --
        mem[ 0] = 8'h11;  mem[ 1] = 8'h31;   // ADDI R1, R1, 1
        mem[ 2] = 8'h10;  mem[ 3] = 8'h01;   // ADD  R1, R0, R1
        mem[ 4] = 8'h10;  mem[ 5] = 8'h01;
        mem[ 6] = 8'h10;  mem[ 7] = 8'h01;
        mem[ 8] = 8'h10;  mem[ 9] = 8'h01;
        mem[10] = 8'h10;  mem[11] = 8'h01;
        mem[12] = 8'h10;  mem[13] = 8'h01;
        mem[14] = 8'h10;  mem[15] = 8'h01;
        mem[16] = 8'h10;  mem[17] = 8'h01;
        mem[18] = 8'hEE;  mem[19] = 8'h6F;   // JMP -0x112  (wrap)
`endif
    end

    always @(*) begin
        instruction = { mem[address + 16'd1], mem[address] };
    end

endmodule
