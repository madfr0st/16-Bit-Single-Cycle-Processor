// =============================================================================
// gpu_tb.v  --  Behavioural testbench for the gpulite32 GPU
// =============================================================================
//   iverilog -g2012 -I cores/gpulite32/rtl \
//       -o build_sim/gpulite32.vvp \
//       cores/gpulite32/sim/gpu_tb.v cores/gpulite32/rtl/*.v
//   vvp build_sim/gpulite32.vvp
//   gtkwave dump.vcd
//
// The default kernel is the paint demo (clear -> hline -> single pixel);
// expected canvas:
//
//     . . . . . . . .       row 0
//     . . . . . . . .       row 1
//     . . . . . . . .       row 2
//     # # # # # # # #       row 3   <-- hline color 0xAA
//     . . . . . . . .       row 4
//     . . . . . # . .       row 5   <-- single pixel (5,5) color 0xFF
//     . . . . . . . .       row 6
//     . . . . . . . .       row 7
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

    // ---- Pretty-print the 8x8 framebuffer ---------------------------------
    task print_canvas;
        integer r, c, word_idx;
        reg [31:0] px;
        begin
            $display("\n   .---- 8x8 framebuffer ----.");
            $display("    col: 0   1   2   3   4   5   6   7");
            for (r = 0; r < 8; r = r + 1) begin
                $write("r=%0d |  ", r);
                for (c = 0; c < 8; c = c + 1) begin
                    word_idx = r * 8 + c;
                    px = uut.GMEM.mem[word_idx];
                    if (px == 32'h0) $write("  . ");
                    else             $write(" %02h ", px[7:0]);
                end
                $write("\n");
            end
            $display("   `------------------------'");
        end
    endtask

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, gpu_tb);

        $display(" time |  PC        | INSTR      | ACT MASK | EXIT");
        $display("------+------------+------------+----------+-----");

        rst = 1;
        #25;
        rst = 0;

        repeat (300) begin
            @(posedge clk);
            // Limit instruction trace to first ~16 cycles to keep output readable
            if ($time < 200) begin
                $display("%5t | %08h   | %08h   |   %b  |  %1b",
                         $time, pc_debug, instr_debug, active_mask, exit_warp);
            end
            if (exit_warp) begin
                $display("---- EXIT reached at t=%0t ----", $time);
                print_canvas();
                $finish;
            end
        end

        $display("\n---- Timed out (300 cycles, no EXIT) ----");
        print_canvas();
        $finish;
    end

endmodule
