// =============================================================================
// gpu_tb.v  --  Behavioural testbench for the gpulite32 GPU
// =============================================================================
//   iverilog -g2012 -I cores/gpulite32/rtl \
//       -o build_sim/gpulite32.vvp \
//       cores/gpulite32/sim/gpu_tb.v cores/gpulite32/rtl/*.v
//   vvp build_sim/gpulite32.vvp
//   gtkwave dump.vcd
//
// Expected output after EXIT:
//   GLOBAL[0..28] = { 0, 1, 4, 9, 16, 25, 36, 49 }
// (lane i wrote i*i to byte address i*4)
// =============================================================================
`timescale 1ns / 1ps

`include "defines.v"

module gpu_tb;

    reg clk;
    reg rst;

    wire        exit_warp;
    wire [31:0] pc_debug;
    wire [31:0] instr_debug;
    wire [`WARP_SIZE-1:0] active_mask;

    gpu uut (
        .clk               (clk),
        .rst               (rst),
        .exit_warp_out     (exit_warp),
        .pc_debug          (pc_debug),
        .instr_debug       (instr_debug),
        .active_mask_debug (active_mask)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, gpu_tb);

        $display(" time |  PC        | INSTR      | ACT MASK | EXIT");
        $display("------+------------+------------+----------+-----");

        rst = 1;
        #25;
        rst = 0;

        repeat (40) begin
            @(posedge clk);
            $display("%5t | %08h   | %08h   |   %b  |  %1b",
                     $time, pc_debug, instr_debug, active_mask, exit_warp);
            if (exit_warp) begin
                $display("---- Warp EXIT reached ----\n");
                $display("Global memory contents (first 8 words):");
                $display(" addr | word value | expected (lane^2)");
                $display(" 0x00 | %08h   |  0", uut.GMEM.mem[0]);
                $display(" 0x04 | %08h   |  1", uut.GMEM.mem[1]);
                $display(" 0x08 | %08h   |  4", uut.GMEM.mem[2]);
                $display(" 0x0C | %08h   |  9", uut.GMEM.mem[3]);
                $display(" 0x10 | %08h   | 16", uut.GMEM.mem[4]);
                $display(" 0x14 | %08h   | 25", uut.GMEM.mem[5]);
                $display(" 0x18 | %08h   | 36", uut.GMEM.mem[6]);
                $display(" 0x1C | %08h   | 49", uut.GMEM.mem[7]);
                $finish;
            end
        end

        $display("\n---- Timed out (40 cycles, no EXIT) ----");
        $finish;
    end

endmodule
