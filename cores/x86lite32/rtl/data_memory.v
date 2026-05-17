// =============================================================================
// data_memory.v  --  4 KB byte-addressed RAM, word-granular for x86lite32
// =============================================================================
// Combinational 32-bit reads, synchronous 32-bit writes (word-aligned only;
// real x86 obviously supports unaligned access, but we don't, for simplicity).
//
// Address arithmetic uses bits [11:2] (word index). Top bits beyond the
// memory are ignored.
// =============================================================================
`timescale 1ns / 1ps

module data_memory #(
    parameter DEPTH_WORDS = 1024     // 4 KB
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
            // synthesis translate_off
            $display("[DM] WRITE addr=%08h data=%08h", addr, wdata);
            // synthesis translate_on
        end
    end

    always @(*) begin
        rdata = re ? mem[word_idx] : 32'h0;
    end

endmodule
