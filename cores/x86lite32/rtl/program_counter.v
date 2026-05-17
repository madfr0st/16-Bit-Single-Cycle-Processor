// =============================================================================
// program_counter.v  --  32-bit PC for x86lite32
// =============================================================================
// Priority on each rising clock edge (async reset to 0):
//   1. rst                           -> PC = 0
//   2. halt                          -> PC unchanged forever
//   3. branch_taken                  -> PC = branch_target          (jumps, conditionals)
//   4. ret_taken                     -> PC = ret_target             (RET reads stack)
//   5. (default)                     -> PC = PC + 4
//
// Note: instructions are 4 bytes wide, so the straight-line increment is +4.
// =============================================================================
`timescale 1ns / 1ps

module program_counter (
    input  wire        clk,
    input  wire        rst,
    input  wire        halt,
    input  wire        branch_taken,
    input  wire [31:0] branch_target,
    input  wire        ret_taken,
    input  wire [31:0] ret_target,
    output reg  [31:0] pc_out
);

    always @(posedge clk or posedge rst) begin
        if (rst)               pc_out <= 32'h0000_0000;
        else if (halt)         pc_out <= pc_out;
        else if (ret_taken)    pc_out <= ret_target;
        else if (branch_taken) pc_out <= branch_target;
        else                   pc_out <= pc_out + 32'd4;
    end

endmodule
