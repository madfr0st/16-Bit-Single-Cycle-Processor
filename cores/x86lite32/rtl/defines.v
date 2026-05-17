// =============================================================================
// defines.v  --  x86lite32 ISA and microarchitecture constants
// =============================================================================
// x86lite32 is a single-cycle, 32-bit, *x86-flavoured* educational CPU.
// It captures the design philosophy of x86 without trying to be x86:
//
//   * Two-operand instructions:  op dst, src    (dst is also a source)
//   * 16 GPRs (R0..R15); R15 doubles as stack pointer (ESP)
//   * Explicit condition-flags register: { OF, SF, ZF, CF }
//   * Conditional jumps decode flag combinations  (JE/JNE/JG/JL/...)
//   * Stack-based PUSH / POP / CALL / RET
//   * Memory addressing: base + 16-bit signed displacement
//
// Major simplification vs. real x86:
//   * Fixed 32-bit instructions (real x86 is 1..15 bytes, variable length)
//   * One memory access per instruction (real x86 can do reg-mem-reg in one)
//   * No segments, no privilege rings, no virtual memory, no microcode
//
// INSTRUCTION FORMAT (fixed 32 bits)
//
//   31     24 23    20 19    16 15                              0
//  +---------+--------+--------+--------------------------------+
//  | opcode  |   dst  |   src  |          immediate / disp      |
//  +---------+--------+--------+--------------------------------+
//
//   8 bits opcode  -> up to 256 instructions
//   4 bits dst     -> R0..R15
//   4 bits src     -> R0..R15
//  16 bits imm     -> sign-extended to 32 (for ADD-imm, LD/ST disp, jumps...)
//
// =============================================================================
`ifndef X86LITE32_DEFINES_V
`define X86LITE32_DEFINES_V

// ---- Opcodes ---------------------------------------------------------------
// Data movement
`define OP_MOV_RR    8'h00   // MOV dst, src              dst <- src
`define OP_MOV_RI    8'h01   // MOV dst, #imm             dst <- sext(imm)
`define OP_LD        8'h02   // LD  dst, [src + disp]     dst <- MEM[src+disp]
`define OP_ST        8'h03   // ST  [src + disp], dst     MEM[src+disp] <- dst

// Arithmetic / logical (set flags)
`define OP_ADD       8'h10   // ADD dst, src              dst <- dst + src
`define OP_SUB       8'h11   // SUB dst, src              dst <- dst - src
`define OP_AND       8'h12   // AND dst, src              dst <- dst & src
`define OP_OR        8'h13   // OR  dst, src              dst <- dst | src
`define OP_XOR       8'h14   // XOR dst, src              dst <- dst ^ src
`define OP_CMP       8'h15   // CMP dst, src              flags <- dst - src   (no writeback)
`define OP_ADDI      8'h16   // ADD dst, #imm             dst <- dst + sext(imm)
`define OP_SUBI      8'h17   // SUB dst, #imm             dst <- dst - sext(imm)
`define OP_CMPI      8'h18   // CMP dst, #imm             flags <- dst - sext(imm)

// Shifts
`define OP_SHL       8'h20   // SHL dst, src              dst <- dst << src[4:0]
`define OP_SHR       8'h21   // SHR dst, src              dst <- dst >> src    (logical)
`define OP_SAR       8'h22   // SAR dst, src              dst <- dst >>> src   (arithmetic)

// Unary
`define OP_INC       8'h30   // INC dst                   dst <- dst + 1
`define OP_DEC       8'h31   // DEC dst                   dst <- dst - 1
`define OP_NEG       8'h32   // NEG dst                   dst <- -dst
`define OP_NOT       8'h33   // NOT dst                   dst <- ~dst

// Stack
`define OP_PUSH      8'h40   // PUSH dst                  ESP -= 4; MEM[ESP] <- dst
`define OP_POP       8'h41   // POP  dst                  dst <- MEM[ESP]; ESP += 4

// Control flow (use 16-bit signed imm as PC-relative offset in bytes)
`define OP_JMP       8'h50   // JMP rel
`define OP_JE        8'h51   // JE  rel   if ZF=1
`define OP_JNE       8'h52   // JNE rel   if ZF=0
`define OP_JG        8'h53   // JG  rel   if ZF=0 & SF=OF       (signed >)
`define OP_JL        8'h54   // JL  rel   if SF!=OF             (signed <)
`define OP_JGE       8'h55   // JGE rel   if SF=OF
`define OP_JLE       8'h56   // JLE rel   if ZF=1 | SF!=OF
`define OP_CALL      8'h57   // CALL rel  ESP-=4; MEM[ESP]<-ret; PC<-PC+rel
`define OP_RET       8'h58   // RET       PC <- MEM[ESP]; ESP+=4

// Misc
`define OP_HLT       8'hFF   // HLT       freeze PC

// ---- Special registers -----------------------------------------------------
`define ESP_INDEX    4'd15   // R15 doubles as the stack pointer

// ---- Flag bit positions inside the 4-bit FLAGS register --------------------
`define FLAG_CF      0       // carry / borrow
`define FLAG_ZF      1       // zero
`define FLAG_SF      2       // sign  (MSB of result)
`define FLAG_OF      3       // signed overflow

// ---- ALU operation codes (internal to the ALU, NOT the opcodes above) -----
`define ALU_ADD      4'h0
`define ALU_SUB      4'h1
`define ALU_AND      4'h2
`define ALU_OR       4'h3
`define ALU_XOR      4'h4
`define ALU_SHL      4'h5
`define ALU_SHR      4'h6
`define ALU_SAR      4'h7
`define ALU_PASS_B   4'h8   // pass src through  (used for MOV reg,reg)
`define ALU_NOT      4'h9
`define ALU_NEG      4'hA

`endif
