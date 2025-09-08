`timescale 1ns / 1ps

module CPU (
    input  wire        clk,
    input  wire        rst,
    output wire [15:0] led, 
    output wire [6:0]  seg, 
    output wire [3:0]  an   
);

wire [15:0] pc_out, instruction, ALU_result;
wire [15:0] data_rs, data_rd, mem_out;
wire [15:0] reg_write_data, sign_extended_imm;

wire        reg_write, mem_read, mem_write, byte_enable, mux_sel;
wire [3:0]  ALU_op;
wire        immi_enable;

wire [3:0] opcode, rs, rd, immidiate;
wire [11:0] jmp_diff;
wire        inc, branch, jmp;


assign inc    = 1'b1;
assign led = data_rd;

seven_segment_controller display_ctrl (
    .clk(clk),
    .rst(rst),
    .value(pc_out), 
    .seg(seg),
    .an(an)
);

program_counter PC (
    .clk         (clk),
    .rst         (rst),
    .inc         (inc),
    .branch      (branch),
    .new_address (ALU_result),
    .pc_out      (pc_out),
    .jmp         (jmp)
);

instruction_memory IM (
    .address     (pc_out),
    .instruction (instruction)
);

assign opcode    = instruction[15:12];
assign rd        = instruction[11: 8];
assign rs        = instruction[ 7: 4];
assign immidiate = instruction[ 3: 0];
assign jmp_diff  = instruction[11: 0];

Control_Unit CU (
    .instruction (instruction),
    .ALU_op      (ALU_op),
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
    .mem_out   (mem_out),
    .rs        (rs),
    .rd        (rd),
    .data_in   (reg_write_data),
    .data_rs   (data_rs),
    .data_rd   (data_rd)
);

sign_extend SE (
    .in  (immidiate),
    .out (sign_extended_imm)
);

ALU alu (
    .A           (data_rd),
    .B           (data_rs),
    .C           (sign_extended_imm),
    .pc_out      (pc_out),
    .ALU_op      (ALU_op),
    .immi_enable (immi_enable),
    .Result      (ALU_result),
    .inc         (inc),
    .branch      (branch),
    .jmp         (jmp),
    .jmp_diff    ({{4{jmp_diff[11]}}, jmp_diff})
);

data_memory DM (
    .clk        (clk), .rst(rst),
    .mem_read   (mem_read),
    .mem_write  (mem_write),
    .byte_enable(byte_enable),
    .address    (ALU_result),
    .data_in    (data_rd),
    .data_out   (mem_out)
);

mux_2to1 MUX (
    .in0 (ALU_result),
    .in1 (mem_out),
    .sel (mux_sel),
    .out (reg_write_data)
);

endmodule

