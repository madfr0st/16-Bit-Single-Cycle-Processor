// =============================================================================
// cpu.v  --  Top-level: a 16-bit single-cycle processor
// =============================================================================
// Every instruction is fetched, decoded, executed, memory-accessed, and
// written back inside ONE rising edge of `clk`. The combinational cone from
// PC -> IM -> Decode -> RF read -> ALU -> DM -> Writeback mux determines the
// minimum clock period (this is the classic single-cycle tradeoff: simplicity
// of control at the cost of cycle time).
//
// Pin-out matches the Basys 3 FPGA (see constraints/basys3.xdc).
//   led       : low 16 bits of register Rd from the currently-executing
//               instruction. Acts as a live register-window for the demo.
//   seg, an   : 4-digit 7-segment display, scanned, showing pc_out in hex.
// =============================================================================
`timescale 1ns / 1ps

module cpu (
    input  wire        clk,
    input  wire        rst,
    output wire [15:0] led,
    output wire [6:0]  seg,
    output wire [3:0]  an
);

    // -------------------------------------------------------------------------
    // Datapath wires
    // -------------------------------------------------------------------------
    wire [15:0] pc_out;
    wire [15:0] instruction;
    wire [15:0] alu_result;
    wire [15:0] data_rs, data_rd;
    wire [15:0] mem_out;
    wire [15:0] reg_write_data;
    wire [15:0] sign_extended_imm;

    // -------------------------------------------------------------------------
    // Control wires (driven by control_unit)
    // -------------------------------------------------------------------------
    wire       reg_write;
    wire       mem_read;
    wire       mem_write;
    wire       byte_enable;
    wire       mux_sel;
    wire       immi_enable;
    wire       jmp;
    wire       branch;       // driven by ALU when a branch condition is met
    wire [3:0] alu_op;

    // -------------------------------------------------------------------------
    // Instruction field slicing (see docs/ISA.md)
    //   [15:12] opcode    [11:8] rd    [7:4] rs    [3:0] imm/funct
    //   [11:0]  jmp_diff  (signed PC-relative offset for JMP)
    // -------------------------------------------------------------------------
    wire [3:0]  opcode    = instruction[15:12];
    wire [3:0]  rd        = instruction[11: 8];
    wire [3:0]  rs        = instruction[ 7: 4];
    wire [3:0]  immediate = instruction[ 3: 0];
    wire [11:0] jmp_diff  = instruction[11: 0];

    // PC always tries to increment; jmp/branch override the next-PC inside
    // the program_counter via priority logic.
    wire inc = 1'b1;

    // Visualization: show the destination-register value on the LEDs.
    assign led = data_rd;

    // -------------------------------------------------------------------------
    // Front-end : PC + instruction memory
    // -------------------------------------------------------------------------
    program_counter PC (
        .clk         (clk),
        .rst         (rst),
        .inc         (inc),
        .branch      (branch),
        .jmp         (jmp),
        .new_address (alu_result),
        .pc_out      (pc_out)
    );

    instruction_memory IM (
        .address     (pc_out),
        .instruction (instruction)
    );

    // -------------------------------------------------------------------------
    // Decode : control unit + register-file read
    // -------------------------------------------------------------------------
    control_unit CU (
        .instruction (instruction),
        .alu_op      (alu_op),
        .reg_write   (reg_write),
        .mem_read    (mem_read),
        .mem_write   (mem_write),
        .mux_sel     (mux_sel),
        .byte_enable (byte_enable),
        .immi_enable (immi_enable),
        .jmp         (jmp)
    );

    register_file RF (
        .clk       (clk),
        .rst       (rst),
        .reg_write (reg_write),
        .mem_read  (mem_read),
        .rs        (rs),
        .rd        (rd),
        .data_in   (reg_write_data),
        .mem_out   (mem_out),
        .data_rs   (data_rs),
        .data_rd   (data_rd)
    );

    sign_extend SE (
        .in  (immediate),
        .out (sign_extended_imm)
    );

    // -------------------------------------------------------------------------
    // Execute : ALU also computes branch / jump targets
    // -------------------------------------------------------------------------
    alu ALU (
        .a           (data_rd),
        .b           (data_rs),
        .c           (sign_extended_imm),
        .pc_out      (pc_out),
        .jmp_diff    ({{4{jmp_diff[11]}}, jmp_diff}),  // 12 -> 16 sign extend
        .alu_op      (alu_op),
        .immi_enable (immi_enable),
        .inc         (inc),
        .jmp         (jmp),
        .result      (alu_result),
        .branch      (branch)
    );

    // -------------------------------------------------------------------------
    // Memory : data memory (combinational read, synchronous write)
    // -------------------------------------------------------------------------
    data_memory DM (
        .clk         (clk),
        .rst         (rst),
        .mem_read    (mem_read),
        .mem_write   (mem_write),
        .byte_enable (byte_enable),
        .address     (alu_result),
        .data_in     (data_rd),
        .data_out    (mem_out)
    );

    // -------------------------------------------------------------------------
    // Writeback : pick ALU result (R/I-type) or memory output (LW)
    //   mux_sel = 0 -> ALU result    mux_sel = 1 -> mem_out
    // Note: register_file already chooses mem_out internally when mem_read=1,
    // so this mux is also routed for instructions like SW that pass through.
    // -------------------------------------------------------------------------
    mux_2to1 WB_MUX (
        .in0 (alu_result),
        .in1 (mem_out),
        .sel (mux_sel),
        .out (reg_write_data)
    );

    // -------------------------------------------------------------------------
    // 7-segment scanner showing pc_out as 4 hex digits
    // -------------------------------------------------------------------------
    seven_segment_controller DISP (
        .clk   (clk),
        .rst   (rst),
        .value (pc_out),
        .seg   (seg),
        .an    (an)
    );

endmodule
