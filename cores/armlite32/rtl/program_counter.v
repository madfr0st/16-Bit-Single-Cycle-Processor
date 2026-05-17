// =============================================================================
// program_counter.v  --  32-bit PC for armlite32
// =============================================================================
// In real ARM, R15 is the PC and is part of the register file. It also reads
// as "current instruction address + 8" because of the classic 3-stage pipeline
// quirk. That quirk is NOT emulated here -- the PC reads as the current
// instruction's address (the cleaner academic convention).
//
// Priority (async reset to 0):
//   1. rst                -> 0
//   2. branch_taken       -> branch_target          (B / BL / cond-taken)
//   3. pc_we_from_rf      -> rf_pc_data             (writing R15 via DP/LDR)
//   4. (default)          -> PC + 4
// =============================================================================
`timescale 1ns / 1ps

module program_counter (
    input  wire        clk,
    input  wire        rst,
    input  wire        branch_taken,
    input  wire [31:0] branch_target,
    input  wire        pc_we_from_rf,
    input  wire [31:0] rf_pc_data,
    output reg  [31:0] pc_out
);

    always @(posedge clk or posedge rst) begin
        if (rst)                pc_out <= 32'h0000_0000;
        else if (branch_taken)  pc_out <= branch_target;
        else if (pc_we_from_rf) pc_out <= rf_pc_data;
        else                    pc_out <= pc_out + 32'd4;
    end

endmodule
