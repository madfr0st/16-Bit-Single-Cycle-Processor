// =============================================================================
// lane.v  --  one SIMT lane (one "CUDA core" + its private register state)
// =============================================================================
// A lane is everything that is REPLICATED per thread inside a warp:
//   * 16 x 32-bit register file
//   * 4-bit predicate register file
//   * 32-bit ALU
//
// All lanes in a warp see THE SAME instruction and control signals. They
// differ only in:
//   * the values currently in their own registers
//   * their tid.x (the lane index, passed in as a parameter)
//
// Lanes whose predicate evaluates to false silently skip writes. They still
// "execute" the instruction in the sense that the cycle passes; this is
// the cost of SIMT divergence -- divergent lanes still occupy hardware time.
// =============================================================================
`timescale 1ns / 1ps

`include "defines.v"

module lane #(
    parameter LANE_ID = 0
) (
    input  wire        clk,
    input  wire        rst,

    // Instruction fields broadcast to all lanes
    input  wire [3:0]  dst_idx,
    input  wire [3:0]  src1_idx,
    input  wire [3:0]  src2_idx,
    input  wire [10:0] imm11,
    input  wire        pred_neg,
    input  wire [2:0]  pred_idx,

    // Control signals from decoder
    input  wire [3:0]  alu_op,
    input  wire        alu_b_imm,
    input  wire        reg_we,
    input  wire        reg_wb_mem,
    input  wire        reg_wb_tid,
    input  wire        reg_wb_ntid,
    input  wire        pred_we,
    input  wire [2:0]  pred_op,         // 0=EQ 1=NE 2=LT 3=LE 4=GT 5=GE

    // Memory subsystem: per-lane address out, per-lane data in/out
    input  wire        mem_re,
    input  wire        mem_we,
    input  wire [31:0] mem_rdata,
    output wire [31:0] mem_addr_lane,
    output wire [31:0] mem_wdata_lane,
    output wire        lane_mem_re,
    output wire        lane_mem_we,

    // Per-lane visibility
    output wire        lane_active        // 1 if predicate is true this cycle
);

    // ---- Per-lane register state -----------------------------------------
    reg [31:0] regs [0:15];
    reg [3:0]  preds;                    // P0..P3
    integer    i;

    // ---- Sign-extend the 11-bit immediate to 32 bits ----------------------
    wire [31:0] imm32 = {{21{imm11[10]}}, imm11};

    // ---- Read sources -----------------------------------------------------
    wire [31:0] src1_data = regs[src1_idx];
    wire [31:0] src2_data = regs[src2_idx];

    // ---- Predicate evaluation ---------------------------------------------
    wire pred_raw     = (pred_idx == 3'b111) ? 1'b1 : preds[pred_idx[1:0]];
    wire pred_passes  = pred_neg ? ~pred_raw : pred_raw;

    assign lane_active = pred_passes;

    // ---- ALU --------------------------------------------------------------
    wire [31:0] alu_b   = alu_b_imm ? imm32 : src2_data;
    wire [31:0] alu_a   = src1_data;
    wire [31:0] alu_out;

    alu ALU (
        .a      (alu_a),
        .b      (alu_b),
        .op     (alu_op),
        .result (alu_out)
    );

    // ---- Per-lane memory port: addr = src1 + imm, data = dst register -----
    // (For ST, dst is the *data*, src1 is the base register; same form as
    //  scp16 / x86lite32. The shared/global mux happens at the top level.)
    assign mem_addr_lane  = src1_data + imm32;
    assign mem_wdata_lane = regs[dst_idx];
    assign lane_mem_re    = mem_re & pred_passes;
    assign lane_mem_we    = mem_we & pred_passes;

    // ---- Predicate compare result (signed comparison) ---------------------
    reg pred_result;
    always @(*) begin
        case (pred_op)
            3'd0: pred_result = (src1_data == src2_data);                    // EQ
            3'd1: pred_result = (src1_data != src2_data);                    // NE
            3'd2: pred_result = ($signed(src1_data) <  $signed(src2_data));  // LT
            3'd3: pred_result = ($signed(src1_data) <= $signed(src2_data));  // LE
            3'd4: pred_result = ($signed(src1_data) >  $signed(src2_data));  // GT
            3'd5: pred_result = ($signed(src1_data) >= $signed(src2_data));  // GE
            default: pred_result = 1'b0;
        endcase
    end

    // ---- Writeback mux ----------------------------------------------------
    wire [31:0] wb_data =
        reg_wb_tid   ? {{(32-`LANE_ID_BITS){1'b0}}, LANE_ID[`LANE_ID_BITS-1:0]} :
        reg_wb_ntid  ? `WARP_SIZE :
        reg_wb_mem   ? mem_rdata :
                       alu_out;

    // ---- Synchronous writes (gated by predicate) --------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 16; i = i + 1) regs[i]  <= 32'h0;
            preds <= 4'h0;
        end
        else begin
            if (reg_we  & pred_passes) regs[dst_idx]                  <= wb_data;
            // Predicate writes target the predicate index inside imm11[1:0]
            // (the low bits of the immediate are re-purposed as the SETP P-target).
            if (pred_we & pred_passes) preds[imm11[1:0]]              <= pred_result;
        end
    end

endmodule
