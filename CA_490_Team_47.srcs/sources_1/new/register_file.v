`timescale 1ns / 1ps

module register_file(
    input clk, rst, reg_write, mem_read,
    input [3:0] rs, rd,
    input [15:0] data_in, mem_out,
    output reg [15:0] data_rs, data_rd
);

    reg [15:0] registers [0:15]; 
    integer i;  

    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 16; i = i + 1) begin
                registers[i] = 16'b0000000000000000;
            end
        end else if (reg_write && !mem_read) begin
            registers[rd] <= data_in; 
        end else if (mem_read) begin
            registers[rd] <= mem_out; 
  
          
        end
    end

    
    always @(*) begin
        data_rs = registers[rs];  
        data_rd = registers[rd];  
    end

endmodule