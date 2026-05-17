// =============================================================================
// defines.v  --  gpulite32 ISA and microarchitecture constants
// =============================================================================
// gpulite32 is a single-cycle, 32-bit, NVIDIA-flavoured educational GPU. It
// captures the SIMT (Single Instruction, Multiple Threads) execution model
// that defines NVIDIA hardware: ONE instruction stream is broadcast to
// MULTIPLE lanes, each lane has its OWN register state, and per-lane
// PREDICATES gate which lanes are active for each instruction.
//
// MICROARCHITECTURE (tiny by NVIDIA standards, but exactly the same shape)
//   * 1 Streaming Multiprocessor (SM)
//   * 1 warp scheduler  (real NVIDIA SMs have 4)
//   * WARP_SIZE = 8     (real NVIDIA warps are 32; shrunk to 8 for sim sanity)
//   * 8 CUDA-style integer lanes, each with:
//        - 16 x 32-bit register file
//        - 4-bit predicate register file
//        - private ALU
//        - private thread ID (tid.x = lane number)
//   * 4 KB shared memory  (single-banked, conflict-free here)
//   * 16 KB global memory
//
// INSTRUCTION FORMAT (fixed 32 bits, PTX-flavoured)
//
//   31     27 26    24 23 22 21    18 17    14 13    10 9                  0
//  +--------+------+--+-----+------+------+------+--------------------------+
//  | opcode | pred |!P| reg | dst  | src1 | src2 |  imm12 / addr / offset   |
//  +--------+------+--+-----+------+------+------+--------------------------+
//       5       3   1   (unused)    4       4       4              12
//
//   Wait, that doesn't fit cleanly. Re-organise:
//
//   31    28 27   26 25  22 21  18 17  14 13                          0
//  +---------+------+-----+-----+-----+-----------------------------+
//  |  opcode |!P pi | dst | src1| src2|         imm14 / offset      |
//  +---------+------+-----+-----+-----+-----------------------------+
//       4       3     4     4     4              14
//
//   opcode (4)  -> 16 instructions (sufficient for a teaching ISA)
//   !P     (1)  -> 1 = negate predicate test
//   pi     (2)  -> predicate index (P0..P3); pi=3 + !P=0 = "always" convention,
//                  but to keep it explicit a 5th opcode bit is reserved below.
//
//  To keep things readable the actual format is slightly larger:
//
//   31    27 26 25  23 22  19 18  15 14  11 10                        0
//  +---------+--+-----+-----+-----+-----+---------------------------+
//  |  opcode |!P| pi  | dst | src1| src2|     imm11 / offset        |
//  +---------+--+-----+-----+-----+-----+---------------------------+
//       5     1    3    4     4     4             11
//
//   pi=3'b111  -> "always" predicate (alias for P_TRUE)
//   pi=0..3    -> predicate registers P0..P3 (lane-private)
//   !P=1       -> execute when the chosen predicate is FALSE
// =============================================================================
`ifndef GPULITE32_DEFINES_V
`define GPULITE32_DEFINES_V

// ---- Warp size -------------------------------------------------------------
`define WARP_SIZE      8
`define LANE_ID_BITS   3

// ---- Opcodes (5 bits, room for 32 instructions) ----------------------------
// -- Data movement
`define OP_MOV_RR    5'h00   // dst <- src1
`define OP_MOV_RI    5'h01   // dst <- sext(imm)
`define OP_S2R_TID   5'h02   // dst <- lane_id              (special register: %tid.x)
`define OP_S2R_NTID  5'h03   // dst <- WARP_SIZE            (%ntid.x)

// -- Arithmetic / logical (all lanes execute, masked by predicate)
`define OP_ADD       5'h08
`define OP_SUB       5'h09
`define OP_MUL       5'h0A
`define OP_AND       5'h0B
`define OP_OR        5'h0C
`define OP_XOR       5'h0D
`define OP_SHL       5'h0E
`define OP_SHR       5'h0F
`define OP_ADDI      5'h10   // dst <- src1 + sext(imm)
`define OP_MULI      5'h11   // dst <- src1 * sext(imm)

// -- Predicate writes  (per-lane comparison -> per-lane predicate)
`define OP_SETP_EQ   5'h14   // P[pi] <- (src1 == src2)
`define OP_SETP_NE   5'h15
`define OP_SETP_LT   5'h16   // signed
`define OP_SETP_LE   5'h17
`define OP_SETP_GT   5'h18
`define OP_SETP_GE   5'h19

// -- Memory
`define OP_LD_G      5'h1A   // dst <- GLOBAL[src1 + imm]
`define OP_ST_G      5'h1B   // GLOBAL[src1 + imm] <- dst
`define OP_LD_S      5'h1C   // dst <- SHARED[src1 + imm]
`define OP_ST_S      5'h1D   // SHARED[src1 + imm] <- dst

// -- Control flow + sync + exit
`define OP_BRA       5'h1E   // warp-PC <- warp-PC + imm   (taken if predicate true on ANY active lane)
`define OP_BAR_EXIT  5'h1F   // dual-use:
                             //   imm[10] = 1  -> EXIT  (HLT the warp)
                             //   imm[10] = 0  -> BAR.SYNC (no-op with 1 warp)

// ---- Predicate aliases -----------------------------------------------------
`define PRED_ALWAYS  3'b111   // when pi=7 the instruction unconditionally runs

`endif
