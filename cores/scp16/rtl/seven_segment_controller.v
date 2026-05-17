// =============================================================================
// seven_segment_controller.v  --  scanning 4-digit hex display (Basys 3)
// =============================================================================
// Drives the Basys 3 onboard 4-digit common-anode 7-segment display.
//
// Pin mapping (from constraints/basys3.xdc):
//   seg[6:0] = {g, f, e, d, c, b, a}   active-LOW segments
//   an[3:0]  = digit-enable             active-LOW (one digit at a time)
//
// The eye perceives a digit as "on" if it is refreshed faster than ~1 kHz.
// We split a counter and use the top two bits as `active_digit` so each
// digit is refreshed at roughly clk / 2^18.  With a 100 MHz clk on the
// Basys 3 that's ~380 Hz per digit -> flicker-free.
//
// Shows the full 16-bit `value` as four hex nibbles, MSB on digit 3.
// =============================================================================
`timescale 1ns / 1ps

module seven_segment_controller (
    input  wire        clk,
    input  wire        rst,
    input  wire [15:0] value,
    output reg  [6:0]  seg,
    output reg  [3:0]  an
);

    // ---- Refresh / scan counter -------------------------------------------
    reg [17:0] refresh_cnt;
    wire [1:0] active_digit = refresh_cnt[17:16];

    always @(posedge clk or posedge rst) begin
        if (rst) refresh_cnt <= 18'd0;
        else     refresh_cnt <= refresh_cnt + 18'd1;
    end

    // ---- Digit select + nibble pick ---------------------------------------
    reg [3:0] digit_value;

    always @(*) begin
        case (active_digit)
            2'b00: begin an = 4'b1110; digit_value = value[ 3: 0]; end
            2'b01: begin an = 4'b1101; digit_value = value[ 7: 4]; end
            2'b10: begin an = 4'b1011; digit_value = value[11: 8]; end
            2'b11: begin an = 4'b0111; digit_value = value[15:12]; end
        endcase
    end

    // ---- Hex -> 7-segment encoder (active LOW) ----------------------------
    //   bit order: { g, f, e, d, c, b, a }
    always @(*) begin
        case (digit_value)
            4'h0: seg = 7'b1000000;  // 0
            4'h1: seg = 7'b1111001;  // 1
            4'h2: seg = 7'b0100100;  // 2
            4'h3: seg = 7'b0110000;  // 3
            4'h4: seg = 7'b0011001;  // 4
            4'h5: seg = 7'b0010010;  // 5
            4'h6: seg = 7'b0000010;  // 6
            4'h7: seg = 7'b1111000;  // 7
            4'h8: seg = 7'b0000000;  // 8
            4'h9: seg = 7'b0010000;  // 9
            4'hA: seg = 7'b0001000;  // A
            4'hB: seg = 7'b0000011;  // b
            4'hC: seg = 7'b1000110;  // C
            4'hD: seg = 7'b0100001;  // d
            4'hE: seg = 7'b0000110;  // E
            4'hF: seg = 7'b0001110;  // F
            default: seg = 7'b1111111;
        endcase
    end

endmodule
