// =============================================================================
// cpu_tb.v  --  Behavioural testbench for x86lite32
// =============================================================================
//   iverilog -g2012 -I cores/x86lite32/rtl \
//        -o build_sim/x86lite32.vvp \
//        cores/x86lite32/sim/cpu_tb.v cores/x86lite32/rtl/*.v
//   vvp build_sim/x86lite32.vvp
//   gtkwave dump.vcd
// =============================================================================
`timescale 1ns / 1ps

module cpu_tb;

    reg clk;
    reg rst;

    wire        halt_out;
    wire [31:0] pc_debug;
    wire [31:0] instr_debug;
    wire [31:0] dst_debug;
    wire [3:0]  flags_debug;

    cpu uut (
        .clk        (clk),
        .rst        (rst),
        .halt_out   (halt_out),
        .pc_debug   (pc_debug),
        .instr_debug(instr_debug),
        .dst_debug  (dst_debug),
        .flags_debug(flags_debug)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, cpu_tb);

        $display(" time |  PC        | INSTR      | DST_REG    | FLAGS(OSZC) | HALT");
        $display("------+------------+------------+------------+-------------+-----");

        rst = 1;
        #25;
        rst = 0;

        // Run until halt or timeout
        repeat (200) begin
            @(posedge clk);
            $display("%5t | %08h   | %08h   | %08h   |    %b    |  %1b",
                     $time, pc_debug, instr_debug, dst_debug, flags_debug, halt_out);
            if (halt_out) begin
                $display("---- CPU halted ----");
                $finish;
            end
        end

        $display("---- Timed out (200 cycles, no HLT) ----");
        $finish;
    end

endmodule
