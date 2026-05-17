// =============================================================================
// register_file.v  --  16 x 32-bit GPRs (R0..R15) for x86lite32
// =============================================================================
// 2 async read ports (dst-read, src-read) + 1 sync write port.
// R15 is the stack pointer (ESP). It's NOT special inside this module -- it's
// just a normal register -- but PUSH/POP/CALL/RET in the top level always
// target it explicitly, plus they update it with ALU's +/-4.
//
// The initial value of R15 (ESP) is the top of the data-memory window so a
// program can use the stack from cycle 0. You can override this from outside
// by raising rst while loading a fresh program.
// =============================================================================
`timescale 1ns / 1ps

`include "defines.v"

module register_file #(
    parameter ESP_INIT = 32'h0000_0FFC   // top of 4 KB data mem, word aligned
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        we,
    input  wire [3:0]  rd_idx,
    input  wire [3:0]  rs_idx,
    input  wire [3:0]  wr_idx,
    input  wire [31:0] wr_data,

    // ESP side-port: PUSH/POP/CALL/RET update ESP in parallel with normal write
    input  wire        esp_we,
    input  wire [31:0] esp_new,

    output wire [31:0] rd_data,
    output wire [31:0] rs_data,
    output wire [31:0] esp_data
);

    reg [31:0] regs [0:15];
    integer    i;

    // ---- Async read --------------------------------------------------------
    assign rd_data  = regs[rd_idx];
    assign rs_data  = regs[rs_idx];
    assign esp_data = regs[`ESP_INDEX];

    // ---- Sync write --------------------------------------------------------
    // Priority: esp_we beats we when both target R15 in the same cycle
    // (e.g. POP into R15 itself -> the ESP-side update wins, mirroring
    // x86's "pop esp" behaviour).
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 16; i = i + 1) regs[i] <= 32'h0;
            regs[`ESP_INDEX] <= ESP_INIT;
        end
        else begin
            if (we && wr_idx != `ESP_INDEX)         regs[wr_idx]      <= wr_data;
            else if (we && wr_idx == `ESP_INDEX && !esp_we)
                                                     regs[`ESP_INDEX] <= wr_data;
            if (esp_we)                              regs[`ESP_INDEX] <= esp_new;
        end
    end

endmodule
