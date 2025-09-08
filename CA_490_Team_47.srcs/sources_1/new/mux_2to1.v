`timescale 1ns / 1ps

module mux_2to1 (
    input [15:0] in0, in1,
    input sel,   
    output reg [15:0] out
);

    always @(*) begin
        if (sel) begin
            out = in1;
        end else begin
            out = in0;
        end
    end
endmodule
