`timescale 1ns / 1ps


module sign_extend (
    input [3:0] in,        
    output reg [15:0] out  
);

    always @(*) begin
        out = {{12{in[3]}}, in};
    end
endmodule
