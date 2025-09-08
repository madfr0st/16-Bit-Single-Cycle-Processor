`timescale 1ns / 1ps

module instruction_memory (
    input  [15:0] address,       
    output reg [15:0] instruction
);
    reg [7:0] mem [0:1000];

    initial begin
        mem[0] = 8'h11;   
        mem[1] = 8'h31;
        mem[2] = 8'h10;  
        mem[3] = 8'h01;  
        mem[4] = 8'h10;   
        mem[5] = 8'h01;
        mem[4] = 8'h10;  
        mem[5] = 8'h01;
        mem[6] = 8'h10;  
        mem[7] = 8'h01;
        mem[8] = 8'h10;  
        mem[9] = 8'h01;
        mem[10] = 8'h10; 
        mem[11] = 8'h01;
        mem[12] = 8'h10;  
        mem[13] = 8'h01;
        mem[14] = 8'h10;  
        mem[15] = 8'h01;
        mem[16] = 8'h10; 
        mem[17] = 8'h01; 
        mem[18] = 8'hee;  
        mem[19] = 8'h6f;
    end
    always @(*) begin
        instruction = { mem[address + 1], mem[address] };
    end
endmodule