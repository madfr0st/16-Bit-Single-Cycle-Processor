// =============================================================================
// register_file.v  --  16 x 32-bit GPRs for armlite32
// =============================================================================
// Two combinational read ports (Rn, Rm) plus a synchronous write port (Rd).
// In real ARM the PC is R15; here we expose R15 read combinationally (so the
// top level can route PC -> R15 read), but writes to R15 trigger a PC update
// outside this module (see cpu.v / program_counter.v).
//
// We treat R15 as a normal storage register here but provide an external
// `pc_in` hook so the top level can keep R15 in sync with the actual PC.
// =============================================================================
`timescale 1ns / 1ps

`include "defines.v"

module register_file (
    input  wire        clk,
    input  wire        rst,
    input  wire        we,
    input  wire [3:0]  rn_idx,
    input  wire [3:0]  rm_idx,
    input  wire [3:0]  wr_idx,
    input  wire [31:0] wr_data,
    // PC mirror: the top level writes PC into R15 every cycle so that
    // reads of R15 reflect the current PC. (Real ARM exposes PC+8.)
    input  wire [31:0] pc_in,
    output wire [31:0] rn_data,
    output wire [31:0] rm_data
);

    reg [31:0] regs [0:15];
    integer    i;

    // ---- Async read (R15 always reflects pc_in) ---------------------------
    assign rn_data = (rn_idx == `REG_PC) ? pc_in : regs[rn_idx];
    assign rm_data = (rm_idx == `REG_PC) ? pc_in : regs[rm_idx];

    // ---- Sync write -------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 16; i = i + 1) regs[i] <= 32'h0;
        end
        else if (we) begin
            regs[wr_idx] <= wr_data;
        end
    end

endmodule
