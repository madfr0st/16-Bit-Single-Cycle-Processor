// =============================================================================
// cpu_tb.v  --  Behavioural testbench for armlite32
// =============================================================================
//   iverilog -g2012 -I cores/armlite32/rtl \
//        -o build_sim/armlite32.vvp \
//        cores/armlite32/sim/cpu_tb.v cores/armlite32/rtl/*.v
//   vvp build_sim/armlite32.vvp
//   gtkwave dump.vcd
// =============================================================================
`timescale 1ns / 1ps

module cpu_tb;

    reg clk;
    reg rst;

    wire [31:0] pc_debug;
    wire [31:0] instr_debug;
    wire [31:0] rd_debug;
    wire [3:0]  cpsr_debug;

    cpu uut (
        .clk        (clk),
        .rst        (rst),
        .pc_debug   (pc_debug),
        .instr_debug(instr_debug),
        .rd_debug   (rd_debug),
        .cpsr_debug (cpsr_debug)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, cpu_tb);

        $display(" time |  PC        | INSTR      | WB_DATA    | CPSR(NZCV)");
        $display("------+------------+------------+------------+----------");

        rst = 1;
        #25;
        rst = 0;

        // Run a fixed number of cycles; the demo program eventually B's to
        // itself (a self-loop standing in for HLT).
        repeat (60) begin
            @(posedge clk);
            $display("%5t | %08h   | %08h   | %08h   |   %b",
                     $time, pc_debug, instr_debug, rd_debug, cpsr_debug);
        end

        // Inspect R2 -- should hold 1+2+...+10 = 55 after the loop.
        $display("\nFinal R2 = %0d (expect 55)", uut.RF.regs[2]);
        $finish;
    end

endmodule
