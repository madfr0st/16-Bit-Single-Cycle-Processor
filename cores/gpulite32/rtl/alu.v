// =============================================================================
// alu.v  --  per-lane 32-bit integer ALU (CUDA-core analog)
// =============================================================================
// Each lane instantiates one of these. Identical to a generic integer ALU --
// the *parallelism* is purely structural (you put 8 of them in parallel).
// In real NVIDIA SMs each CUDA core is essentially this: a 32-bit FMA-capable
// FP + INT lane. This design stays integer-only for clarity.
// =============================================================================
`timescale 1ns / 1ps

module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  op,
    output reg  [31:0] result
);

    always @(*) begin
        case (op)
            4'h0: result = a + b;                 // ADD
            4'h1: result = a - b;                 // SUB
            4'h2: result = a * b;                 // MUL (lower 32 bits)
            4'h3: result = a & b;                 // AND
            4'h4: result = a | b;                 // OR
            4'h5: result = a ^ b;                 // XOR
            4'h6: result = a << b[4:0];           // SHL
            4'h7: result = a >> b[4:0];           // SHR (logical)
            default: result = 32'h0;
        endcase
    end

endmodule
