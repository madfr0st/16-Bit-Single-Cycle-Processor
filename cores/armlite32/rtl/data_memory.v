// =============================================================================
// data_memory.v  --  word-addressed 4 KB RAM for armlite32
// =============================================================================
// Combinational reads, synchronous writes. Word access only (real ARM also
// supports byte / halfword via LDRB / LDRH / STRB / STRH; we omit those).
//
// Addresses are byte addresses; word index is addr[11:2].
// =============================================================================
`timescale 1ns / 1ps

module data_memory #(
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
            // synthesis translate_off
            $display("[DM] WRITE addr=%08h data=%08h", addr, wdata);
            // synthesis translate_on
        end
    end

    always @(*) begin
        rdata = re ? mem[word_idx] : 32'h0;
    end

endmodule
