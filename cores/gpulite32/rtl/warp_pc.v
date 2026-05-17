// =============================================================================
// warp_pc.v  --  Program counter for the single warp in gpulite32
// =============================================================================
// In a real NVIDIA SM, each warp has its own PC and the warp scheduler picks
// which warp to issue from on each cycle (so 4 warps issuing one instruction
// per cycle can fill 128 CUDA cores in 8 cycles). Here exactly ONE warp is
// modelled, so the scheduler degenerates to "tick the PC".
//
// Priority (async reset to 0):
//   1. rst       -> 0
//   2. exit      -> hold forever
//   3. branch    -> branch_target
//   4. default   -> PC + 4
// =============================================================================
`timescale 1ns / 1ps

module warp_pc (
    input  wire        clk,
    input  wire        rst,
    input  wire        exit_warp,
    input  wire        branch_taken,
    input  wire [31:0] branch_target,
    output reg  [31:0] pc_out
);

    always @(posedge clk or posedge rst) begin
        if (rst)               pc_out <= 32'h0;
        else if (exit_warp)    pc_out <= pc_out;        // halt
        else if (branch_taken) pc_out <= branch_target;
        else                   pc_out <= pc_out + 32'd4;
    end

endmodule
