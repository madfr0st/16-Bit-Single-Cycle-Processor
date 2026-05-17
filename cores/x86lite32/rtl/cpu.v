// =============================================================================
// cpu.v  --  x86lite32 top level
// =============================================================================
// A 32-bit single-cycle CPU in the *style* of x86: two-operand instructions,
// EFLAGS-style condition flags, stack-based PUSH/POP/CALL/RET, conditional
// jumps that decode flag combinations.
//
// One instruction completes per rising edge. The critical-path cone is:
//   PC -> IM -> Decode -> RF read -> ALU -> (DM for LD/POP/RET) -> WB mux
// (parallel branch: -> flags_reg cond logic -> next-PC mux)
// =============================================================================
`timescale 1ns / 1ps

`include "defines.v"

module cpu (
    input  wire        clk,
    input  wire        rst,
    output wire        halt_out,
    output wire [31:0] pc_debug,
    output wire [31:0] instr_debug,
    output wire [31:0] dst_debug,
    output wire [3:0]  flags_debug
);

    // ---------------- Datapath wires ---------------------------------------
    wire [31:0] pc_out;
    wire [31:0] instruction;
    wire [31:0] dst_data, src_data, esp_data;
    wire [31:0] alu_a, alu_b, alu_result;
    wire [31:0] mem_addr, mem_rdata, mem_wdata;
    wire [31:0] writeback_data;
    wire [3:0]  alu_flags;
    wire [3:0]  flags_q;

    // ---------------- Control signals --------------------------------------
    wire [3:0] alu_op;
    wire       alu_b_imm, alu_a_zero, alu_a_src;
    wire       reg_we, reg_wb_mem;
    wire       mem_re, mem_we, mem_addr_sel, mem_wdata_sel;
    wire       flags_update;
    wire signed [31:0] esp_delta;
    wire       esp_we;
    wire       is_jump, is_cond_jump, is_ret, halt;
    wire [3:0] cond_code;

    // ---------------- Instruction field slicing ----------------------------
    wire [7:0]  opcode = instruction[31:24];
    wire [3:0]  dst    = instruction[23:20];
    wire [3:0]  src    = instruction[19:16];
    wire [15:0] imm16  = instruction[15: 0];
    wire [31:0] imm32  = {{16{imm16[15]}}, imm16};   // sign extend

    // ---- For INC / DEC the immediate is overridden to +-1 via this mux ----
    wire is_inc = (opcode == `OP_INC);
    wire is_dec = (opcode == `OP_DEC);
    wire [31:0] effective_imm =
        is_inc ? 32'd1 :
        is_dec ? 32'd1 :
                 imm32;

    assign halt_out    = halt;
    assign pc_debug    = pc_out;
    assign instr_debug = instruction;
    assign dst_debug   = dst_data;
    assign flags_debug = flags_q;

    // ---------------- Front-end --------------------------------------------
    wire        branch_taken;
    wire [31:0] branch_target;

    program_counter PC (
        .clk           (clk),
        .rst           (rst),
        .halt          (halt),
        .branch_taken  (branch_taken),
        .branch_target (branch_target),
        .ret_taken     (is_ret),
        .ret_target    (mem_rdata),
        .pc_out        (pc_out)
    );

    instruction_memory IM (
        .address     (pc_out),
        .instruction (instruction)
    );

    // ---------------- Decode -----------------------------------------------
    control_unit CU (
        .instruction   (instruction),
        .alu_op        (alu_op),
        .alu_b_imm     (alu_b_imm),
        .alu_a_zero    (alu_a_zero),
        .alu_a_src     (alu_a_src),
        .reg_we        (reg_we),
        .reg_wb_mem    (reg_wb_mem),
        .mem_re        (mem_re),
        .mem_we        (mem_we),
        .mem_addr_sel  (mem_addr_sel),
        .mem_wdata_sel (mem_wdata_sel),
        .flags_update  (flags_update),
        .esp_delta     (esp_delta),
        .esp_we        (esp_we),
        .is_jump       (is_jump),
        .is_cond_jump  (is_cond_jump),
        .cond_code     (cond_code),
        .is_ret        (is_ret),
        .halt          (halt)
    );

    register_file RF (
        .clk      (clk),
        .rst      (rst),
        .we       (reg_we),
        .rd_idx   (dst),
        .rs_idx   (src),
        .wr_idx   (dst),
        .wr_data  (writeback_data),
        .esp_we   (esp_we),
        .esp_new  (esp_data + esp_delta),
        .rd_data  (dst_data),
        .rs_data  (src_data),
        .esp_data (esp_data)
    );

    // ---------------- Execute ----------------------------------------------
    // ALU A operand priority:  alu_a_zero > alu_a_src > dst
    //   alu_a_zero=1  (MOV_RI)  -> A = 0   so PASS_B(imm) yields imm
    //   alu_a_src=1   (LD / ST) -> A = src so addr = src + imm
    //   otherwise              -> A = dst
    assign alu_a = alu_a_zero ? 32'h0
                  : alu_a_src ? src_data
                              : dst_data;
    assign alu_b = alu_b_imm  ? effective_imm : src_data;

    alu ALU (
        .a          (alu_a),
        .b          (alu_b),
        .op         (alu_op),
        .result     (alu_result),
        .flags_next (alu_flags)
    );

    // ---------------- Flags + branch decision ------------------------------
    wire cond_e, cond_ne, cond_g, cond_l, cond_ge, cond_le;

    flags_reg FLAGS (
        .clk       (clk),
        .rst       (rst),
        .update    (flags_update),
        .flags_in  (alu_flags),
        .flags_out (flags_q),
        .cond_e    (cond_e),
        .cond_ne   (cond_ne),
        .cond_g    (cond_g),
        .cond_l    (cond_l),
        .cond_ge   (cond_ge),
        .cond_le   (cond_le)
    );

    reg cond_match;
    always @(*) begin
        case (cond_code)
            4'h0: cond_match = cond_e;
            4'h1: cond_match = cond_ne;
            4'h2: cond_match = cond_g;
            4'h3: cond_match = cond_l;
            4'h4: cond_match = cond_ge;
            4'h5: cond_match = cond_le;
            default: cond_match = 1'b0;
        endcase
    end

    assign branch_taken  = is_jump | (is_cond_jump & cond_match);
    assign branch_target = pc_out + 32'd4 + imm32;     // x86-style relative offset

    // ---------------- Memory address + write-data muxes --------------------
    assign mem_addr  = mem_addr_sel ? (esp_data + (esp_delta == -32'sd4 ? -32'sd4 : 32'sd0))
                                    :  alu_result;
    //   PUSH/CALL store TO new ESP (= ESP-4): pre-subtract here so the
    //   write hits the right slot in the same cycle the ESP register is
    //   updated.
    //   POP/RET  read  FROM old ESP, so esp_delta=+4 contributes 0 here.

    assign mem_wdata = mem_wdata_sel ? (pc_out + 32'd4)   // CALL: push ret addr
                                     :  dst_data;         // PUSH/ST: data

    data_memory DM (
        .clk   (clk),
        .rst   (rst),
        .we    (mem_we),
        .re    (mem_re),
        .addr  (mem_addr),
        .wdata (mem_wdata),
        .rdata (mem_rdata)
    );

    // ---------------- Write-back mux ---------------------------------------
    assign writeback_data = reg_wb_mem ? mem_rdata : alu_result;

endmodule
