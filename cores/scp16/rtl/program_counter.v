// =============================================================================
// program_counter.v  --  16-bit PC with reset / branch / jump / increment
// =============================================================================
// Priority on each rising edge of clk (async-reset to 0):
//   1. rst    -> PC = 0
//   2. jmp    -> PC = new_address              (J-type)
//   3. branch -> PC = new_address              (BEQ / BNE taken)
//   4. inc    -> PC = PC + 2                   (instructions are 2 bytes wide)
//   5. else   -> PC unchanged                  (hold)
//
// PC adds 2 because the instruction memory is byte-addressed and one
// instruction = 16 bits = 2 bytes (little-endian inside instruction_memory.v).
// =============================================================================
`timescale 1ns / 1ps

module program_counter (
    input  wire        clk,
    input  wire        rst,
    input  wire        inc,
    input  wire        branch,
    input  wire        jmp,
    input  wire [15:0] new_address,
    output reg  [15:0] pc_out
);

    always @(posedge clk or posedge rst) begin
        if (rst)
            pc_out <= 16'h0000;
        else if (jmp)
            pc_out <= new_address;
        else if (branch)
            pc_out <= new_address;
        else if (inc)
            pc_out <= pc_out + 16'd2;
        // else: hold
    end

endmodule
