`timescale 1ns / 1ps

module seven_segment_controller(
    input wire clk,            
    input wire rst,            
    input wire [15:0] value,   
    output reg [6:0] seg,      
    output reg [3:0] an        
);
   
    wire [1:0] active_digit;
    reg [3:0] digit_value;
    
   
    always @(*) begin
        
                digit_value = value[3:0];     
                an = 4'b1110;                 
           
        
    end
    
    
   always @(digit_value) begin
        case (digit_value)
            4'h0: seg = 7'b0000001; 
            4'h1: seg = 7'b0010010; 
            4'h2: seg = 7'b0010010; 
            4'h3: seg = 7'b0000110; 
            4'h4: seg = 7'b1001100; 
            4'h5: seg = 7'b0100100; 
            4'h6: seg = 7'b0100000; 
            4'h7: seg = 7'b0001111; 
            4'h8: seg = 7'b0000000; 
            4'h9: seg = 7'b0001100; 
            4'hA: seg = 7'b0001000; 
            4'hB: seg = 7'b1100000; 
            4'hC: seg = 7'b0110001; 
            4'hD: seg = 7'b1000010; 
            4'hE: seg = 7'b0110000; 
            4'hF: seg = 7'b0111000; 
            default: seg = 7'b0000000; 
        endcase
end
    
endmodule

