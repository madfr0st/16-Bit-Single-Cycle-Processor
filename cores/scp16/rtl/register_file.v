// =============================================================================
// register_file.v  --  16 x 16-bit GPR file (R0..R15)
// =============================================================================
//   2 combinational read ports  (data_rs, data_rd)
//   1 synchronous  write port   (writes Rd at the rising edge of clk)
//
// Write semantics on a clock edge:
//   rst              -> all registers cleared to 0
//   mem_read = 1     -> Rd <- mem_out        (used by LW)
//   reg_write = 1    -> Rd <- data_in        (used by R-type, ADDI, LW path)
//   otherwise        -> hold
//
// NOTE: R0 is a normal register here (not hard-wired to zero like MIPS/RISC-V).
// This was a conscious choice in the original ISA for simplicity; if you
// extend the design, consider adding `if (rd != 0)` to make R0 hard-wired,
// which makes a free "discard" register for branch comparisons.
// =============================================================================
`timescale 1ns / 1ps

module register_file (
    input  wire        clk,
    input  wire        rst,
    input  wire        reg_write,
    input  wire        mem_read,
    input  wire [3:0]  rs,
    input  wire [3:0]  rd,
    input  wire [15:0] data_in,
    input  wire [15:0] mem_out,
    output wire [15:0] data_rs,
    output wire [15:0] data_rd
);

    reg [15:0] registers [0:15];
    integer    i;

    // --- Combinational read ports ------------------------------------------
    assign data_rs = registers[rs];
    assign data_rd = registers[rd];

    // --- Synchronous write port --------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 16; i = i + 1) registers[i] <= 16'h0000;
        end
        else if (mem_read)            registers[rd] <= mem_out;
        else if (reg_write)           registers[rd] <= data_in;
    end

endmodule
