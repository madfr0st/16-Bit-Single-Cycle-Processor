`timescale 1ns / 1ps

module Control_Unit(
    input [15:0] instruction,
    output reg [3:0] ALU_op,
    output reg reg_write, mem_read, mem_write, mux_sel, byte_enable, immi_enable, jmp
);

    always @(*) begin
        case (instruction[15:12])  
            4'b0000: begin 
                case (instruction[3:0]) 
                    4'b0000: ALU_op = 4'b0000; 
                    4'b0001: ALU_op = 4'b0001; 
                    4'b0010: ALU_op = 4'b0010; 
                    4'b0011: ALU_op = 4'b0011; 
                    default: ALU_op = 4'b0000; 
                endcase
                reg_write = 1; mem_read = 0; mem_write = 0; mux_sel = 0; byte_enable = 0; immi_enable = 0; jmp = 0; 
            end
            4'b0001: begin ALU_op = 4'b0000; reg_write = 1; mem_read = 1; mem_write = 0; mux_sel = 0; byte_enable = 0; immi_enable = 1; jmp = 0; end 
            4'b0010: begin ALU_op = 4'b0000; reg_write = 0; mem_read = 0; mem_write = 1; mux_sel = 1; byte_enable = 0; immi_enable = 1; jmp = 0; end 
            4'b0011: begin ALU_op = 4'b0000; reg_write = 1; mem_read = 0; mem_write = 0; mux_sel = 0; byte_enable = 0; immi_enable = 1; jmp = 0; end 
            4'b0100: begin ALU_op = 4'b0001; reg_write = 0; mem_read = 0; mem_write = 0; mux_sel = 0; byte_enable = 0; immi_enable = 1; jmp = 0; end
            4'b0101: begin ALU_op = 4'b0010; reg_write = 0; mem_read = 0; mem_write = 0; mux_sel = 0; byte_enable = 0; immi_enable = 1; jmp = 0; end
            4'b0110: begin ALU_op = 4'b0000; reg_write = 0; mem_read = 0; mem_write = 0; mux_sel = 0; byte_enable = 0; immi_enable = 0; jmp = 1;end 
            default: begin ALU_op = 4'b0000; reg_write = 0; mem_read = 0; mem_write = 0; mux_sel = 0; byte_enable = 0; immi_enable = 0;end 
        endcase          
                 
    end
endmodule