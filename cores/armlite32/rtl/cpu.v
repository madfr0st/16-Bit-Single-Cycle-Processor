// =============================================================================
// cpu.v  --  armlite32 top level
// =============================================================================
// 32-bit single-cycle CPU in the style of ARMv4. The four flagship features
// you can see right here in the wiring:
//
//   1. EVERY instruction is conditional. The `cond_unit` evaluates the 4-bit
//      cond field against CPSR flags every cycle; if false, all writes are
//      gated off and the instruction becomes a NOP. (Branches included.)
//
//   2. Operand2 is a barrel-shifted register OR a rotated immediate. The
//      `barrel_shifter` module produces op2 in pure combinational logic, in
//      time for the ALU.
//
//   3. Load/store-only memory access. Data processing instructions cannot
//      touch memory; only LDR/STR go through `data_memory`.
//
//   4. R15 is the PC. The register file mirrors PC on R15 reads; writes to
//      R15 (e.g. MOV PC, LR for function return) are routed back into the PC.
//
// Critical-path cone:
//   PC -> IM -> Decode + cond_unit -> RF read -> barrel_shifter -> ALU
//        -> (DM for LDR) -> writeback mux -> RF
// =============================================================================
`timescale 1ns / 1ps

`include "defines.v"

module cpu (
    input  wire        clk,
    input  wire        rst,
    output wire [31:0] pc_debug,
    output wire [31:0] instr_debug,
    output wire [31:0] rd_debug,
    output wire [3:0]  cpsr_debug
);

    // ---------------- Datapath wires ---------------------------------------
    wire [31:0] pc;
    wire [31:0] instruction;
    wire [31:0] rn_data, rm_data;
    wire [31:0] op2;
    wire [31:0] alu_result;
    wire [31:0] mem_addr, mem_rdata;
    wire [31:0] writeback;
    wire [3:0]  alu_flags;
    wire [3:0]  cpsr_flags;
    wire        cond_execute;

    // ---------------- Instruction field slicing ----------------------------
    wire [3:0]  cond   = instruction[31:28];
    wire [3:0]  rn_idx = instruction[19:16];
    wire [3:0]  rd_idx = instruction[15:12];
    wire [3:0]  rm_idx = instruction[3:0];
    wire [4:0]  shamt  = instruction[11:7];
    wire [1:0]  shtype = instruction[6:5];
    wire [3:0]  imm_rot= instruction[11:8];
    wire [7:0]  imm8   = instruction[7:0];
    wire [11:0] ls_off = instruction[11:0];
    wire [23:0] br_off = instruction[23:0];

    // ---------------- Decode -----------------------------------------------
    wire is_dp_imm, is_dp_reg, is_load, is_store, is_branch, is_branch_link;
    wire dp_writeback, set_flags;
    wire use_pre_index, add_offset, ls_writeback;
    wire [3:0] dp_opcode;

    control_unit CU (
        .instruction    (instruction),
        .is_dp_imm      (is_dp_imm),
        .is_dp_reg      (is_dp_reg),
        .is_load        (is_load),
        .is_store       (is_store),
        .is_branch      (is_branch),
        .is_branch_link (is_branch_link),
        .dp_opcode      (dp_opcode),
        .dp_writeback   (dp_writeback),
        .set_flags      (set_flags),
        .use_pre_index  (use_pre_index),
        .add_offset     (add_offset),
        .ls_writeback   (ls_writeback)
    );

    cond_unit CONDU (
        .cond    (cond),
        .flags   (cpsr_flags),
        .execute (cond_execute)
    );

    // ---------------- Register file ----------------------------------------
    // wr_data and the write-enable are gated by cond_execute so a "skipped" instruction
    // truly is a NOP.
    wire any_reg_write =
        (is_dp_reg | is_dp_imm) ? dp_writeback :
         is_load                ? 1'b1         :
         is_branch_link         ? 1'b1         :   // BL writes LR (R14)
                                  1'b0;

    wire        reg_we;
    wire [3:0]  wr_idx;
    wire [31:0] wr_data;

    // STR needs to read Rd (the data source). The register file has only
    // two read ports, so the rm port is *repurposed*: during LS, route
    // rd_idx into rm_idx. The barrel shifter's rm_data input is don't-care
    // during LS (alu_b is driven from the immediate offset instead), so
    // this repurposing has no side effects.
    wire [3:0] rm_idx_effective = (is_load | is_store) ? rd_idx : rm_idx;

    register_file RF (
        .clk     (clk),
        .rst     (rst),
        .we      (reg_we),
        .rn_idx  (rn_idx),
        .rm_idx  (rm_idx_effective),
        .wr_idx  (wr_idx),
        .wr_data (wr_data),
        .pc_in   (pc),
        .rn_data (rn_data),
        .rm_data (rm_data)
    );

    // ---------------- Operand2 (barrel shifter) ----------------------------
    barrel_shifter BS (
        .is_imm        (is_dp_imm),
        .rm_data       (rm_data),
        .shift_amount  (shamt),
        .shift_type    (shtype),
        .imm_rot       (imm_rot),
        .imm8          (imm8),
        .op2           (op2)
    );

    // ---------------- ALU --------------------------------------------------
    // For load/store, ALU computes the effective address as rn +/- imm12.
    // For data processing, ALU does the user-visible op on (rn, op2).
    wire [31:0] alu_a = rn_data;
    wire [31:0] alu_b =
        (is_load | is_store) ? (add_offset ? {20'h0, ls_off} : -{20'h0, ls_off})
                             :  op2;
    wire [3:0]  alu_op_eff =
        (is_load | is_store) ? `DP_ADD
                             :  dp_opcode;

    alu ALU (
        .a          (alu_a),
        .b          (alu_b),
        .opcode     (alu_op_eff),
        .cin        (cpsr_flags[`FLAG_C]),
        .result     (alu_result),
        .flags_next (alu_flags)
    );

    // ---------------- CPSR -------------------------------------------------
    cpsr_reg CPSR (
        .clk      (clk),
        .rst      (rst),
        .update   (cond_execute & set_flags & (is_dp_imm | is_dp_reg)),
        .flags_in (alu_flags),
        .flags_out(cpsr_flags)
    );

    // ---------------- Data memory ------------------------------------------
    assign mem_addr = alu_result;

    data_memory DM (
        .clk   (clk),
        .rst   (rst),
        .we    (cond_execute & is_store),
        .re    (cond_execute & is_load),
        .addr  (mem_addr),
        .wdata (rm_data),        // STR data: rm port repurposed to Rd above
        .rdata (mem_rdata)
    );

    // ---------------- Writeback --------------------------------------------
    // Default destination is Rd. For BL the destination redirects to LR.
    assign wr_idx  = is_branch_link ? `REG_LR : rd_idx;
    assign wr_data = is_branch_link ? (pc + 32'd4) :
                     is_load        ? mem_rdata    :
                                       alu_result;
    assign reg_we  = cond_execute & any_reg_write;

    // ---------------- Branch target + PC update ----------------------------
    //   branch_target = PC + 8 + sext24(br_off) * 4
    //   (the "+8" mimics ARM's pipelined PC convention; here it's a constant)
    wire signed [31:0] br_offset_bytes = {{6{br_off[23]}}, br_off, 2'b00};
    wire        [31:0] branch_target   = pc + 32'd8 + br_offset_bytes;

    program_counter PC (
        .clk            (clk),
        .rst            (rst),
        .branch_taken   (cond_execute & is_branch),
        .branch_target  (branch_target),
        .pc_we_from_rf  (cond_execute & (any_reg_write & (wr_idx == `REG_PC))),
        .rf_pc_data     (wr_data),
        .pc_out         (pc)
    );

    instruction_memory IM (
        .address     (pc),
        .instruction (instruction)
    );

    // ---------------- Debug exports ----------------------------------------
    assign pc_debug    = pc;
    assign instr_debug = instruction;
    assign rd_debug    = wr_data;
    assign cpsr_debug  = cpsr_flags;

endmodule
