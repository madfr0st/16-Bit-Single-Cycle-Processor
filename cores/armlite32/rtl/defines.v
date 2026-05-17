// =============================================================================
// defines.v  --  armlite32 ISA and microarchitecture constants
// =============================================================================
// armlite32 is a single-cycle, 32-bit, *ARM-flavoured* educational CPU. The
// encoding mirrors ARMv4's data-processing / load-store / branch formats so
// that anyone who has seen real ARM machine code will recognise it.
//
// MAJOR DESIGN HALLMARKS (inherited from ARM)
//   * Fixed 32-bit instructions  (no Thumb)
//   * Load/store-only memory access (cannot use memory operands in ADD etc.)
//   * EVERY instruction has a 4-bit condition code (the famous "conditional
//     execution") -- it is skipped if the flags don't match the predicate
//   * Three-operand data processing:   op Rd, Rn, <Operand2>
//   * Operand2 is either a shifted register or a rotated immediate
//   * R15 is the PC, R14 is the link register (LR), R13 is the stack pointer
//   * CPSR flag bits N (negative), Z (zero), C (carry), V (overflow)
//
// INSTRUCTION FORMATS (we implement a subset)
//
//   Data-processing register-form (I=0):
//   31  28 27 25 24    21 20 19  16 15 12 11  7 6 5 4 3   0
//  +-----+----+--------+--+-----+-----+-----+---+--+-----+
//  | cond|000 | opcode | S| Rn  | Rd  |shamt|sh |0 | Rm  |
//  +-----+----+--------+--+-----+-----+-----+---+--+-----+
//
//   Data-processing immediate-form (I=1):
//   31  28 27 25 24    21 20 19  16 15 12 11  8 7        0
//  +-----+----+--------+--+-----+-----+-----+-----------+
//  | cond|001 | opcode | S| Rn  | Rd  | rot |    imm8   |
//  +-----+----+--------+--+-----+-----+-----+-----------+
//
//   Load/Store immediate offset:
//   31  28 27 25 24 23 22 21 20 19  16 15 12 11                     0
//  +-----+----+--+--+--+--+--+-----+-----+-----------------------+
//  | cond|010 | P| U| B| W| L| Rn  | Rd  |        imm12          |
//  +-----+----+--+--+--+--+--+-----+-----+-----------------------+
//
//   Branch / Branch-with-Link:
//   31  28 27 25 24 23                                       0
//  +-----+----+--+----------------------------------------+
//  | cond|101 | L|              signed_imm24              |
//  +-----+----+--+----------------------------------------+
//
//   (Real ARM has many more formats: multiply, swap, status-reg, coprocessor,
//    Thumb, ...; we omit them for clarity.)
// =============================================================================
`ifndef ARMLITE32_DEFINES_V
`define ARMLITE32_DEFINES_V

// ---- 4-bit condition codes (real ARM mnemonics) ----------------------------
`define COND_EQ  4'h0    // Z set
`define COND_NE  4'h1    // Z clear
`define COND_CS  4'h2    // C set         (unsigned >=)
`define COND_CC  4'h3    // C clear       (unsigned <)
`define COND_MI  4'h4    // N set         (negative)
`define COND_PL  4'h5    // N clear       (non-negative)
`define COND_VS  4'h6    // V set         (overflow)
`define COND_VC  4'h7    // V clear
`define COND_HI  4'h8    // C set & Z clear  (unsigned >)
`define COND_LS  4'h9    // C clear | Z set  (unsigned <=)
`define COND_GE  4'hA    // N == V           (signed >=)
`define COND_LT  4'hB    // N != V           (signed <)
`define COND_GT  4'hC    // Z clear & N == V (signed >)
`define COND_LE  4'hD    // Z set | N != V   (signed <=)
`define COND_AL  4'hE    // always
`define COND_NV  4'hF    // never (reserved in real ARM; treated as never here)

// ---- Top-3-bit "type" field bits[27:25] ------------------------------------
`define TYPE_DP_REG  3'b000   // data-processing, Op2 = shifted register
`define TYPE_DP_IMM  3'b001   // data-processing, Op2 = rotated immediate
`define TYPE_LS_IMM  3'b010   // load/store with immediate offset
`define TYPE_BR      3'b101   // branch / branch-and-link

// ---- Data-processing opcodes (bits[24:21]) ---------------------------------
`define DP_AND  4'h0   // Rd = Rn AND op2
`define DP_EOR  4'h1   // Rd = Rn XOR op2
`define DP_SUB  4'h2   // Rd = Rn - op2
`define DP_RSB  4'h3   // Rd = op2 - Rn      (reverse subtract)
`define DP_ADD  4'h4   // Rd = Rn + op2
`define DP_ADC  4'h5   // Rd = Rn + op2 + C
`define DP_SBC  4'h6   // Rd = Rn - op2 - !C
`define DP_RSC  4'h7   // Rd = op2 - Rn - !C
`define DP_TST  4'h8   // flags = Rn AND op2 (no writeback)
`define DP_TEQ  4'h9   // flags = Rn XOR op2 (no writeback)
`define DP_CMP  4'hA   // flags = Rn - op2   (no writeback)
`define DP_CMN  4'hB   // flags = Rn + op2   (no writeback)
`define DP_ORR  4'hC   // Rd = Rn OR  op2
`define DP_MOV  4'hD   // Rd = op2           (Rn ignored)
`define DP_BIC  4'hE   // Rd = Rn AND ~op2
`define DP_MVN  4'hF   // Rd = ~op2

// ---- Shift types (Op2 register form, bits[6:5]) ----------------------------
`define SH_LSL  2'b00   // logical shift left
`define SH_LSR  2'b01   // logical shift right
`define SH_ASR  2'b10   // arithmetic shift right
`define SH_ROR  2'b11   // rotate right

// ---- Special register indices ---------------------------------------------
`define REG_SP  4'd13
`define REG_LR  4'd14
`define REG_PC  4'd15

// ---- CPSR flag positions inside our 4-bit flag bus -------------------------
//      We pack {N, Z, C, V}.
`define FLAG_N  3
`define FLAG_Z  2
`define FLAG_C  1
`define FLAG_V  0

`endif
