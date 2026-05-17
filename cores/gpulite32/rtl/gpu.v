// =============================================================================
// gpu.v  --  top level for the single-SM gpulite32 GPU
// =============================================================================
// One Streaming Multiprocessor (SM), one warp, 8 SIMT lanes.
//
//   +-----------------------------------------------------------+
//   |                          SM                                |
//   |                                                            |
//   |  +--------+    +------+     +-------------+                |
//   |  | warp   |--->|  IM  |---->|  decode +   |                |
//   |  |  PC    |    +------+     |  predicate  |                |
//   |  +--------+                 +------+------+                |
//   |       ^                            |                       |
//   |       |       (control signals broadcast to all lanes)     |
//   |       |       +---------+---------+---------+----+         |
//   |       |       |         |         |         |    |         |
//   |       |   +---v---+ +---v---+ +---v---+ ... |    |         |
//   |       |   | LANE0 | | LANE1 | | LANE2 |     |    |         |
//   |       |   +---+---+ +---+---+ +---+---+ ... |    |         |
//   |       |       \________________/             /    |         |
//   |       |                |                          |         |
//   |       |        +-------+--------+         +-------v-----+   |
//   |       |        |  Global memory |         | Shared mem  |   |
//   |       |        |  (8-port read /|         | (1 port,    |   |
//   |       |        |   8-write coalesced)|    |  banked HW) |   |
//   |       |        +-------+--------+         +-------------+   |
//   |       |                |                                    |
//   |       +<------ branch_target (if predicate true & is_branch)|
//   |                                                              |
//   +-------------------------------------------------------------+
// =============================================================================
`timescale 1ns / 1ps

`include "defines.v"

module gpu (
    input  wire        clk,
    input  wire        rst,
    output wire        exit_warp_out,
    output wire [31:0] pc_debug,
    output wire [31:0] instr_debug,
    output wire [`WARP_SIZE-1:0] active_mask_debug
);

    // ---- Warp PC + instruction fetch --------------------------------------
    wire        is_exit;
    wire        is_branch;
    wire [31:0] warp_pc;
    wire [31:0] instruction;
    wire [31:0] branch_target;
    wire        branch_taken;

    warp_pc WPC (
        .clk           (clk),
        .rst           (rst),
        .exit_warp     (is_exit),
        .branch_taken  (branch_taken),
        .branch_target (branch_target),
        .pc_out        (warp_pc)
    );

    instruction_memory IM (
        .address     (warp_pc),
        .instruction (instruction)
    );

    // ---- Decode the broadcast fields --------------------------------------
    wire [4:0]  opcode    = instruction[31:27];
    wire        pred_neg  = instruction[26];
    wire [2:0]  pred_idx  = instruction[25:23];
    wire [3:0]  dst_idx   = instruction[22:19];
    wire [3:0]  src1_idx  = instruction[18:15];
    wire [3:0]  src2_idx  = instruction[14:11];
    wire [10:0] imm11     = instruction[10: 0];

    /* verilator lint_off UNUSED */
    wire _unused = |{opcode};
    /* verilator lint_on UNUSED */

    // ---- Control unit (one decoder, drives all lanes) ---------------------
    wire [3:0] alu_op;
    wire       alu_b_imm;
    wire       reg_we;
    wire       reg_wb_mem;
    wire       reg_wb_tid;
    wire       reg_wb_ntid;
    wire       pred_we;
    wire [2:0] pred_op;
    wire       mem_re;
    wire       mem_we;
    wire       is_shared;

    control_unit CU (
        .instruction  (instruction),
        .alu_op       (alu_op),
        .alu_b_imm    (alu_b_imm),
        .reg_we       (reg_we),
        .reg_wb_mem   (reg_wb_mem),
        .reg_wb_tid   (reg_wb_tid),
        .reg_wb_ntid  (reg_wb_ntid),
        .pred_we      (pred_we),
        .pred_op      (pred_op),
        .mem_re       (mem_re),
        .mem_we       (mem_we),
        .is_shared    (is_shared),
        .is_branch    (is_branch),
        .is_exit      (is_exit)
    );

    // ---- 8 lanes ----------------------------------------------------------
    wire [31:0] lane_mem_addr   [0:`WARP_SIZE-1];
    wire [31:0] lane_mem_wdata  [0:`WARP_SIZE-1];
    wire [31:0] lane_mem_rdata  [0:`WARP_SIZE-1];   // per-lane read response
    wire [`WARP_SIZE-1:0] lane_re;
    wire [`WARP_SIZE-1:0] lane_we;
    wire [`WARP_SIZE-1:0] lane_active;

    genvar g;
    generate
        for (g = 0; g < `WARP_SIZE; g = g + 1) begin : LANE
            lane #(.LANE_ID(g)) L (
                .clk            (clk),
                .rst            (rst),
                .dst_idx        (dst_idx),
                .src1_idx       (src1_idx),
                .src2_idx       (src2_idx),
                .imm11          (imm11),
                .pred_neg       (pred_neg),
                .pred_idx       (pred_idx),
                .alu_op         (alu_op),
                .alu_b_imm      (alu_b_imm),
                .reg_we         (reg_we),
                .reg_wb_mem     (reg_wb_mem),
                .reg_wb_tid     (reg_wb_tid),
                .reg_wb_ntid    (reg_wb_ntid),
                .pred_we        (pred_we),
                .pred_op        (pred_op),
                .mem_re         (mem_re & ~is_shared),
                .mem_we         (mem_we & ~is_shared),
                .mem_rdata      (lane_mem_rdata[g]),
                .mem_addr_lane  (lane_mem_addr[g]),
                .mem_wdata_lane (lane_mem_wdata[g]),
                .lane_mem_re    (lane_re[g]),
                .lane_mem_we    (lane_we[g]),
                .lane_active    (lane_active[g])
            );
        end
    endgenerate

    // ---- Global memory: 8-port (per-lane) --------------------------------
    global_memory GMEM (
        .clk        (clk),
        .rst        (rst),
        .lane_re    (lane_re),
        .lane_we    (lane_we),
        .lane_addr  (lane_mem_addr),
        .lane_wdata (lane_mem_wdata),
        .lane_rdata (lane_mem_rdata)
    );

    // ---- Shared memory: single port, lane 0 wins (simplified) ------------
    // (A real banked shared memory would route 8 banks of single-ports; the
    //  semantics are identical when there are no bank conflicts.)
    wire        s_re = mem_re &  is_shared & lane_active[0];
    wire        s_we = mem_we &  is_shared & lane_active[0];
    wire [31:0] s_rdata_dummy;

    shared_memory SMEM (
        .clk   (clk),
        .rst   (rst),
        .we    (s_we),
        .re    (s_re),
        .addr  (lane_mem_addr[0]),
        .wdata (lane_mem_wdata[0]),
        .rdata (s_rdata_dummy)
    );

    /* verilator lint_off UNUSED */
    wire _unused_s = |s_rdata_dummy;
    /* verilator lint_on UNUSED */

    // ---- Branch target ----------------------------------------------------
    // Taken if ANY lane's predicate is true. (Real GPUs use a convergence
    // stack to handle divergence; this design keeps it simple: branch if any-true.)
    wire [31:0] imm32 = {{21{imm11[10]}}, imm11};
    assign branch_target = warp_pc + 32'd4 + (imm32 << 2);
    assign branch_taken  = is_branch & (|lane_active);

    // ---- Debug ------------------------------------------------------------
    assign exit_warp_out      = is_exit;
    assign pc_debug           = warp_pc;
    assign instr_debug        = instruction;
    assign active_mask_debug  = lane_active;

endmodule
