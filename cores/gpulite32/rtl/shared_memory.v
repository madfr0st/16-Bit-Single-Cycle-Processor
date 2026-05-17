// =============================================================================
// shared_memory.v  --  on-SM scratchpad RAM (NVIDIA's "shared memory")
// =============================================================================
// In NVIDIA hardware shared memory is *banked* (32 banks); two lanes
// touching different banks the same cycle is conflict-free, two lanes
// touching the same bank serialise. Modelling banks is overkill for a
// teaching design, so this module exposes a single-port abstraction: in
// each cycle, at most ONE lane reads/writes shared memory. The caller
// (top level) is responsible for arbitrating which lane wins -- here it
// wires lane 0 for simplicity since the demo program doesn't use shared
// memory.
//
// 4 KB, word-addressed.
// =============================================================================
`timescale 1ns / 1ps

module shared_memory #(
    parameter DEPTH_WORDS = 1024
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        we,
    input  wire        re,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata
);

    reg [31:0] mem [0:DEPTH_WORDS-1];
    integer    i;
    wire [9:0] word_idx = addr[11:2];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < DEPTH_WORDS; i = i + 1) mem[i] <= 32'h0;
        end
        else if (we) begin
            mem[word_idx] <= wdata;
        end
    end

    always @(*) begin
        rdata = re ? mem[word_idx] : 32'h0;
    end

endmodule
