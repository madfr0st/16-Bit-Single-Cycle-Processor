// =============================================================================
// data_memory.v  --  byte-addressed RAM with combinational read + sync write
// =============================================================================
// Why combinational reads?
//   In a single-cycle CPU, LW must produce the loaded word on the SAME edge
//   that the register file will latch it. Registered (clocked) reads add a
//   one-cycle skew and silently break LW. So `data_out` is driven
//   purely combinationally from the address; only writes are clocked.
//
// byte_enable:
//   0  -> 16-bit word access (low byte at address, high byte at address+1)
//   1  -> 8-bit byte access  (only the low byte is touched)
// =============================================================================
`timescale 1ns / 1ps

module data_memory #(
    parameter DEPTH_BYTES = 1024
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire        byte_enable,
    input  wire [15:0] address,
    input  wire [15:0] data_in,
    output reg  [15:0] data_out
);

    reg [7:0] mem [0:DEPTH_BYTES-1];
    integer   i;

    // ---- Synchronous reset + write port -----------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < DEPTH_BYTES; i = i + 1) mem[i] <= 8'h00;
        end
        else if (mem_write) begin
            if (byte_enable) begin
                // 8-bit write: only low byte
                mem[address]      <= data_in[7:0];
            end
            else begin
                // 16-bit write: low byte first, high byte at +1
                mem[address]      <= data_in[ 7:0];
                mem[address + 1]  <= data_in[15:8];
            end
            // synthesis-tools ignore $display; useful in simulation only
            // synthesis translate_off
            $display("[DM] WRITE  addr=%h data=%h be=%b", address, data_in, byte_enable);
            // synthesis translate_on
        end
    end

    // ---- Combinational read port ------------------------------------------
    always @(*) begin
        if (!mem_read) begin
            data_out = 16'h0000;
        end
        else if (byte_enable) begin
            data_out = {8'h00, mem[address]};
        end
        else begin
            data_out = {mem[address + 1], mem[address]};
        end
    end

endmodule
