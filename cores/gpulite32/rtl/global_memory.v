// =============================================================================
// global_memory.v  --  off-SM RAM (NVIDIA's "global memory" / HBM stand-in)
// =============================================================================
// In a real GPU this is many GB of HBM / GDDR sitting outside the chip, with
// a multi-level cache hierarchy (L1 -> L2 -> HBM). Here it's a flat 16 KB
// SRAM with one read + one write port that can be SIMT-coalesced across the
// 8 lanes in a warp: if all 8 lanes touch addresses inside the same 32-byte
// cache line in the same cycle, the access "coalesces" into a single memory
// transaction. Coalescing is NOT modelled structurally (it's a performance
// optimisation, not a correctness feature) -- 8 independent ports are
// exposed for simplicity and the caller is expected to serialise or
// coalesce.
//
// To keep the design tractable, the top level uses a single arbiter: in any
// one cycle, at most ONE lane reads or writes global memory. If the program
// is correctly written for coalesced access, real hardware would handle all
// 8 lanes in one transaction; here, a simple priority encoder preserves
// SIMT semantics (results are correct), but throughput is lower than a
// real GPU.
//
// Capacity: 16 KB (4096 words).
// =============================================================================
`timescale 1ns / 1ps

module global_memory #(
    parameter DEPTH_WORDS = 4096
) (
    input  wire        clk,
    input  wire        rst,

    // 8 lane request ports
    input  wire [7:0]        lane_re,
    input  wire [7:0]        lane_we,
    input  wire [31:0]       lane_addr   [0:7],
    input  wire [31:0]       lane_wdata  [0:7],
    output reg  [31:0]       lane_rdata  [0:7]
);

    reg [31:0] mem [0:DEPTH_WORDS-1];
    integer    i;
    integer    l;

    // ---- Cycle 1: synchronous writes from EVERY requesting lane ----------
    // If two lanes write the same word in the same cycle, the higher-indexed
    // lane wins (simple priority). In real HW you would either coalesce or
    // see undefined behaviour for conflicting writes.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < DEPTH_WORDS; i = i + 1) mem[i] <= 32'h0;
        end
        else begin
            for (l = 0; l < 8; l = l + 1) begin
                if (lane_we[l]) begin
                    mem[lane_addr[l][13:2]] <= lane_wdata[l];
                    // synthesis translate_off
                    $display("[GLOBAL] lane%0d WRITE  addr=%08h data=%08h",
                              l, lane_addr[l], lane_wdata[l]);
                    // synthesis translate_on
                end
            end
        end
    end

    // ---- Combinational reads, one per lane -------------------------------
    integer ll;
    always @(*) begin
        for (ll = 0; ll < 8; ll = ll + 1) begin
            lane_rdata[ll] = lane_re[ll] ? mem[lane_addr[ll][13:2]] : 32'h0;
        end
    end

endmodule
