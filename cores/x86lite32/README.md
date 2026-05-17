# x86lite32 &mdash; a 32-bit x86-flavoured single-cycle CPU

> Honest scope: this is **not** an x86 CPU. It is a 32-bit teaching CPU that
> mirrors the *design philosophy* of x86: two-operand instructions, an
> EFLAGS-style condition-flag register, a stack with `PUSH/POP/CALL/RET`, and
> conditional jumps that test flag combinations. Real x86-64 is a 50-year
> CISC ISA implementation with variable-length instructions (1..15 bytes),
> microcode, dozens of addressing modes, and proprietary microarchitecture
> (front-end decode trees, uop cache, OoO back end, etc.) &mdash; way out of
> scope for a teaching core.

## What it implements

- **32-bit** datapath, 32-bit ALU, 32-bit memory
- **16 GPRs** (`R0..R15`); `R15 = ESP` (stack pointer)
- **EFLAGS** subset: `CF`, `ZF`, `SF`, `OF`
- **Two-operand** instruction format: `op dst, src`  (dst is also a source)
- **Stack** primitives: `PUSH`, `POP`, `CALL`, `RET`
- **Conditional jumps**: `JE`, `JNE`, `JG`, `JL`, `JGE`, `JLE`  (and unconditional `JMP`)
- **CISC-ish** unary instructions: `INC`, `DEC`, `NEG`, `NOT`
- Single instruction per clock

## Instruction format

```
   31     24 23    20 19    16 15                              0
  +---------+--------+--------+--------------------------------+
  | opcode  |   dst  |   src  |          immediate / disp      |
  +---------+--------+--------+--------------------------------+
        8        4        4                  16
```

The 16-bit immediate is sign-extended to 32 bits for all uses (addressing
displacement, ADDI value, branch offset).

## Opcode table

| Opcode | Mnemonic | Effect                                                |
|--------|----------|-------------------------------------------------------|
| `00`   | MOV r,r  | `dst <- src`                                          |
| `01`   | MOV r,i  | `dst <- sext(imm)`                                    |
| `02`   | LD       | `dst <- MEM[src + sext(imm)]`                         |
| `03`   | ST       | `MEM[src + sext(imm)] <- dst`                         |
| `10`   | ADD      | `dst <- dst + src` (flags)                            |
| `11`   | SUB      | `dst <- dst - src` (flags)                            |
| `12`   | AND      | `dst <- dst & src` (flags)                            |
| `13`   | OR       | `dst <- dst | src` (flags)                            |
| `14`   | XOR      | `dst <- dst ^ src` (flags)                            |
| `15`   | CMP r,r  | `flags <- dst - src` (no writeback)                   |
| `16`   | ADDI     | `dst <- dst + sext(imm)` (flags)                      |
| `17`   | SUBI     | `dst <- dst - sext(imm)` (flags)                      |
| `18`   | CMPI     | `flags <- dst - sext(imm)` (no writeback)             |
| `20`   | SHL      | `dst <- dst << src[4:0]` (flags)                      |
| `21`   | SHR      | `dst <- dst >> src[4:0]` (logical, flags)             |
| `22`   | SAR      | `dst <- dst >>> src[4:0]` (arithmetic, flags)         |
| `30`   | INC      | `dst <- dst + 1` (flags)                              |
| `31`   | DEC      | `dst <- dst - 1` (flags)                              |
| `32`   | NEG      | `dst <- -dst` (flags)                                 |
| `33`   | NOT      | `dst <- ~dst`                                         |
| `40`   | PUSH     | `ESP -= 4; MEM[ESP] <- dst`                           |
| `41`   | POP      | `dst <- MEM[ESP]; ESP += 4`                           |
| `50`   | JMP rel  | `PC <- PC + 4 + sext(imm)`                            |
| `51`   | JE rel   | branch if `ZF = 1`                                    |
| `52`   | JNE rel  | branch if `ZF = 0`                                    |
| `53`   | JG rel   | branch if `ZF=0 && SF=OF`     (signed >)              |
| `54`   | JL rel   | branch if `SF != OF`           (signed <)             |
| `55`   | JGE rel  | branch if `SF = OF`                                   |
| `56`   | JLE rel  | branch if `ZF=1 || SF != OF`                          |
| `57`   | CALL rel | `ESP-=4; MEM[ESP] <- PC+4; PC <- PC+4 + sext(imm)`    |
| `58`   | RET      | `PC <- MEM[ESP]; ESP += 4`                            |
| `FF`   | HLT      | freeze PC                                             |

## Demo program

The `instruction_memory.v` ships with a small program:

```
PC=0x00  MOV  R1, #1
PC=0x04  MOV  R2, #0
PC=0x08  ADD  R2, R1           ; R2 += R1
PC=0x0C  ADD  R1, R1           ; R1 *= 2
PC=0x10  CMP  R1, #128         ; flags = R1 - 128
PC=0x14  JL   -12              ; back to PC=0x08 while R1 < 128
PC=0x18  HLT
```

It sums `1+2+4+8+16+32+64 = 127` into R2, then halts.

## Run it

```bash
iverilog -g2012 -I cores/x86lite32/rtl \
    -o build_sim/x86lite32.vvp \
    cores/x86lite32/sim/cpu_tb.v cores/x86lite32/rtl/*.v
vvp build_sim/x86lite32.vvp
```

## Files

```
x86lite32/
├── rtl/
│   ├── defines.v               opcodes + ALU codes + constants
│   ├── cpu.v                   top
│   ├── program_counter.v       32-bit PC with halt / branch / ret priorities
│   ├── instruction_memory.v    32-bit word ROM (demo program built in)
│   ├── control_unit.v          opcode -> control signal decoder
│   ├── register_file.v         16x32-bit GPRs; R15=ESP side-port
│   ├── alu.v                   ALU + flag generator (x86 semantics)
│   ├── flags_reg.v             EFLAGS register + condition predicates
│   └── data_memory.v           4 KB word RAM
└── sim/
    └── cpu_tb.v                behavioural testbench
```

## What this teaches that scp16 doesn't

- **Condition flags** &mdash; the CISC pattern where arithmetic instructions
  *implicitly* set status bits and later instructions *implicitly* read them.
- **Stack discipline** &mdash; PUSH/POP/CALL/RET fully working with a
  conventional descending stack on R15=ESP.
- **Side-effecting writes** &mdash; the register file has both a normal
  write port (writes Rd from ALU/mem) and a parallel ESP write port (for
  PUSH/POP/CALL/RET). This mirrors real ISAs where stack ops update SP
  alongside the destination register.
- **Decoder fan-out** &mdash; the control unit emits 17 signals to express
  the variety of behaviours; compare to scp16's 8. Welcome to ISA bloat.
