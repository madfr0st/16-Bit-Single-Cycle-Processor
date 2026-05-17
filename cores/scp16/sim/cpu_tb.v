// =============================================================================
// cpu_tb.v  --  Behavioural testbench for the 16-bit single-cycle CPU
// =============================================================================
// Drives clk and rst, then monitors every interesting datapath signal so a
// waveform viewer (GTKWave, Vivado XSim) tells you a clear story.
//
// Run with Icarus Verilog:
//     iverilog -o cpu_tb.vvp -g2012 \
//        sim/cpu_tb.v rtl/*.v
//     vvp cpu_tb.vvp
//     gtkwave dump.vcd
//
// Run inside Vivado:
//     set as the active simulation top, click Run Simulation -> Behavioral.
// =============================================================================
`timescale 1ns / 1ps

module cpu_tb;

    reg clk;
    reg rst;

    wire [15:0] led;
    wire [6:0]  seg;
    wire [3:0]  an;

    cpu uut (
        .clk (clk),
        .rst (rst),
        .led (led),
        .seg (seg),
        .an  (an)
    );

    // ---- Clock: 100 MHz (10 ns period) ------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ---- VCD dump for GTKWave ---------------------------------------------
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, cpu_tb);
    end

    // ---- Stimulus + monitor -----------------------------------------------
    initial begin
        $display(" time | rst |   PC | Instr | Rs   | Rd   | ALU | Result | rw mr mw | mux ie jmp | mem_out");
        $display("------+-----+------+-------+------+------+-----+--------+----------+------------+--------");
        $monitor("%5t | %1b   | %04h | %04h  | %04h | %04h |  %1h  |  %04h  |  %1b  %1b  %1b  |  %1b   %1b   %1b  | %04h",
            $time,
            rst,
            uut.pc_out,
            uut.instruction,
            uut.data_rs,
            uut.data_rd,
            uut.alu_op,
            uut.alu_result,
            uut.reg_write,
            uut.mem_read,
            uut.mem_write,
            uut.mux_sel,
            uut.immi_enable,
            uut.jmp,
            uut.mem_out);

        rst = 1'b1;
        #25;
        rst = 1'b0;

        // Let the demo program run long enough to exercise:
        //   - ADDI (R1 = 1)
        //   - several ADDs
        //   - the JMP at PC=0x12 that wraps back to PC=0x00
        #2000;

        $display("---- End of simulation ----");
        $finish;
    end

endmodule
