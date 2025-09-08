`timescale 1ns / 1ps

module program_counter(
    input clk, rst, inc, branch, jmp,    
    input [15:0] new_address,            
    output reg [15:0] pc_out             
);

    always @(posedge clk or posedge rst) begin
        if (rst)
            pc_out <= 16'b0;           
        else if (jmp)
            pc_out <= new_address;     
        else if (branch)
            pc_out <= new_address;     
        else if (inc)
            pc_out <= pc_out + 2;      
        else
            pc_out <= pc_out;          
    end

endmodule