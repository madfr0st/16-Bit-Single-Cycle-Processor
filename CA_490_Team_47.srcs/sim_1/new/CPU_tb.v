`timescale 1ns / 1ps
module CPU_tb;
    reg clk;
    reg rst;
    CPU uut (
        .clk(clk), 
        .rst(rst),
        .led()
    );
    always #10 clk = ~clk;
    initial begin
        clk = 0;
        rst = 1;
        $display("     Time | clk | rst |   PC | Instr | Data_RS | Data_RD | ALU_OP | ALU_Result | RegWrite | MemRead | MemWrite | MemData | MuxSel | imI | sign_extended_imm | jmp");
        $monitor("%10t | %3b | %3b | %04h | %04h | %04h | %04h | %1h    | %04h     | %1b       | %1b      | %1b      | %04h   | %1b     | %1b | %04h | %1b", 
                 $time, clk, rst, 
                 uut.pc_out, 
                 uut.instruction, 
                 uut.data_rs, 
                 uut.data_rd, 
                 uut.ALU_op, 
                 uut.ALU_result, 
                 uut.reg_write, 
                 uut.mem_read, 
                 uut.mem_write, 
                 uut.mem_out, 
                 uut.mux_sel, 
                 uut.immi_enable, 
                 uut.sign_extended_imm,
                 uut.jmp);
        #10 rst = 0;

        #10; // Cycle 1
        #10; // Cycle 2
        #10; // Cycle 3
        #10; // Cycle 4
        #10; // Cycle 5
        #10; // Cycle 6
        #10; // Cycle 7
        #10; // Cycle 8
        #10; // Cycle 9
        #10; // Cycle 10
        
        #10; // Cycle 1
        #10; // Cycle 2
        #10; // Cycle 3
        #10; // Cycle 4
        #10; // Cycle 5
        #10; // Cycle 6
        #10; // Cycle 7
        #10; // Cycle 8
        #10; // Cycle 9
        #10; // Cycle 10

        
        #50 $finish;
    end
endmodule
