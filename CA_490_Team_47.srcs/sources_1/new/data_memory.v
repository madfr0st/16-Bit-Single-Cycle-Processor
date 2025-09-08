`timescale 1ns / 1ps
module data_memory (
    input clk,
    input rst,
    input mem_read, mem_write, byte_enable, 
    input [15:0] address,
    input [15:0] data_in,
    output reg [15:0] data_out
);
    reg [7:0] mem [0:1000];  
    integer i;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i <= 1000; i = i + 1) begin
                mem[i] <= 8'h00;  
            end
            data_out <= 16'h0000;                
        end
        else begin
            if (mem_write) begin
                if (byte_enable) begin 
                    mem[address] <= data_in[7:0]; 
                end else begin 
                    mem[address] <= data_in[7:0];      
                    mem[address + 1] <= data_in[15:8]; 
                end
                 $display("Memory Write: Addr = %h, Data = %h", address, data_in);
            end
            if (mem_read) begin
                if (byte_enable) begin 
                    data_out <= {8'b0, mem[address]};  
                end else begin 
                    data_out <= {mem[address + 1], mem[address]};
                end
                  $display("Memory Read: Addr = %h, Data = %h", address, data_out);
            end
        end
    end
endmodule
