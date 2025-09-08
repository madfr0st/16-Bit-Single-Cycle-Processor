`timescale 1ns / 1ps
module ALU (
    input [15:0] A, B, C, jmp_diff ,  
    input [15:0] pc_out,      
    input [3:0] ALU_op,  
        
    input immi_enable, inc, jmp,  
    output reg branch,        
    output reg [15:0] Result  
);
    always @(*) begin
        Result = 16'b0;
        branch = 1'b0;  
        if (immi_enable) begin
            case (ALU_op)
                4'b0000: Result = B + C; 
                4'b0001: begin
                    if (A == B) begin
                        Result = pc_out + C;
                        branch = 1'b1; 
                    end
                end
                4'b0010: begin
                    if (A != B) begin
                        Result = pc_out + C;
                        branch = 1'b1; 
                    end
                end
            endcase
        end else begin
            case (ALU_op)
                4'b0000: Result = A + B; 
                4'b0001: Result = A - B; 
                4'b0010: Result = A << B; 
                4'b0011: Result = A & B; 
            endcase
        end
        if (jmp) begin
            Result = pc_out + jmp_diff;
        end
    end
endmodule