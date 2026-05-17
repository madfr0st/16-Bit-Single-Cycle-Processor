# ISA Reference &mdash; all three cores

This document is the authoritative encoding reference for the CPU cores in
this repo (scp16, x86lite32, armlite32). If you want to write programs by
hand, this is the file to keep open. For the GPU ISA see
[`../cores/gpulite32/README.md`](../cores/gpulite32/README.md).

- [scp16](#scp16-16-bit)
- [x86lite32](#x86lite32-32-bit-cisc-style)
- [armlite32](#armlite32-32-bit-arm-style)
- [Comparative observations](#comparative-observations)

---

## scp16 (16-bit)

### Word layouts

```
R-type  (opcode 0000)
  15      12 11        8 7         4 3      0
 +----------+-----------+-----------+--------+
 |  opcode  |    rd     |    rs     | funct  |
 +----------+-----------+-----------+--------+

I-type  (opcodes 0001..0101)
  15      12 11        8 7         4 3      0
 +----------+-----------+-----------+--------+
 |  opcode  |    rd     |    rs     |  imm4  |   (imm sign-extended to 16)
 +----------+-----------+-----------+--------+

J-type  (opcode 0110)
  15      12 11                              0
 +----------+----------------------------------+
 |  opcode  |          signed jmp_diff         |
 +----------+----------------------------------+
```

Memory is byte-addressed; instructions are 2 bytes wide; PC normally
advances by +2.

### Instructions

| Op | Mnemonic | Encoding (binary)             | Semantics                              |
|----|----------|-------------------------------|----------------------------------------|
| 0  | ADD      | `0000 rd rs 0000`             | `Rd <- Rd + Rs`                        |
| 0  | SUB      | `0000 rd rs 0001`             | `Rd <- Rd - Rs`                        |
| 0  | SLL      | `0000 rd rs 0010`             | `Rd <- Rd << Rs[3:0]`                  |
| 0  | AND      | `0000 rd rs 0011`             | `Rd <- Rd & Rs`                        |
| 1  | LW       | `0001 rd rs imm`              | `Rd <- MEM[Rs + sext(imm)]`            |
| 2  | SW       | `0010 rd rs imm`              | `MEM[Rs + sext(imm)] <- Rd`            |
| 3  | ADDI     | `0011 rd rs imm`              | `Rd <- Rs + sext(imm)`                 |
| 4  | BEQ      | `0100 rd rs imm`              | `if (Rd == Rs) PC <- PC + sext(imm)`   |
| 5  | BNE      | `0101 rd rs imm`              | `if (Rd != Rs) PC <- PC + sext(imm)`   |
| 6  | JMP      | `0110 jmp_diff[11:0]`         | `PC <- PC + sext(jmp_diff)`            |

### Hand-assembly cheatsheet

To encode `ADDI R5, R3, -2`:
```
opcode = 0011
rd     = 0101
rs     = 0011
imm    = 1110   ( = -2 sign extended to 4 bits )
     -> 0011 0101 0011 1110
     -> 0x353E
bytes (little-endian) -> 0x3E 0x35
```

---

## x86lite32 (32-bit, CISC-style)

### Word layout (fixed 32-bit)

```
   31     24 23    20 19    16 15                              0
  +---------+--------+--------+--------------------------------+
  | opcode  |   dst  |   src  |          immediate / disp      |
  +---------+--------+--------+--------------------------------+
        8        4        4                  16
```

The 16-bit immediate field is sign-extended to 32 bits whenever used.

### Opcode table

| Opcode | Mnemonic   | Effect                                                |
|--------|------------|-------------------------------------------------------|
| `00`   | MOV r,r    | `dst <- src`                                          |
| `01`   | MOV r,#i   | `dst <- sext(imm)`                                    |
| `02`   | LD r,[r+i] | `dst <- MEM[src + sext(imm)]`                         |
| `03`   | ST [r+i],r | `MEM[src + sext(imm)] <- dst`                         |
| `10`   | ADD r,r    | `dst <- dst + src`  (flags)                           |
| `11`   | SUB r,r    | `dst <- dst - src`  (flags)                           |
| `12`   | AND r,r    | `dst <- dst & src`  (flags)                           |
| `13`   | OR  r,r    | `dst <- dst \| src` (flags)                           |
| `14`   | XOR r,r    | `dst <- dst ^ src`  (flags)                           |
| `15`   | CMP r,r    | `flags <- dst - src`  (no writeback)                  |
| `16`   | ADD r,#i   | `dst <- dst + sext(imm)` (flags)                      |
| `17`   | SUB r,#i   | `dst <- dst - sext(imm)` (flags)                      |
| `18`   | CMP r,#i   | `flags <- dst - sext(imm)` (no writeback)             |
| `20`   | SHL r,r    | `dst <- dst << src[4:0]` (flags)                      |
| `21`   | SHR r,r    | `dst <- dst >> src[4:0]` (logical, flags)             |
| `22`   | SAR r,r    | `dst <- dst >>> src[4:0]` (arithmetic, flags)         |
| `30`   | INC r      | `dst <- dst + 1` (flags)                              |
| `31`   | DEC r      | `dst <- dst - 1` (flags)                              |
| `32`   | NEG r      | `dst <- -dst` (flags)                                 |
| `33`   | NOT r      | `dst <- ~dst`                                         |
| `40`   | PUSH r     | `ESP -= 4; MEM[ESP] <- dst`                           |
| `41`   | POP  r     | `dst <- MEM[ESP]; ESP += 4`                           |
| `50`   | JMP rel    | `PC <- PC + 4 + sext(imm)`                            |
| `51`   | JE  rel    | branch if `ZF = 1`                                    |
| `52`   | JNE rel    | branch if `ZF = 0`                                    |
| `53`   | JG  rel    | branch if `ZF = 0 && SF = OF`     (signed >)          |
| `54`   | JL  rel    | branch if `SF != OF`               (signed <)         |
| `55`   | JGE rel    | branch if `SF = OF`                                   |
| `56`   | JLE rel    | branch if `ZF = 1 || SF != OF`                        |
| `57`   | CALL rel   | `ESP-=4; MEM[ESP] <- PC+4; PC <- PC+4 + sext(imm)`    |
| `58`   | RET        | `PC <- MEM[ESP]; ESP += 4`                            |
| `FF`   | HLT        | freeze PC                                             |

### Flag rules

| Flag | Set by                                | Cleared by                                |
|------|---------------------------------------|-------------------------------------------|
| CF   | unsigned carry-out of ADD; borrow on SUB | logical ops, MOV, shifts                |
| ZF   | result == 0                           | result != 0                               |
| SF   | result[31]                            | otherwise                                 |
| OF   | signed overflow on ADD/SUB            | logical / MOV / shift                     |

---

## armlite32 (32-bit, ARM-style)

### Word layouts

All instructions are **32-bit fixed**, and the **top 4 bits are the
condition code** &mdash; ARM's hallmark feature.

```
Data-processing register form  (type=000)
 31  28 27 25 24    21 20 19  16 15 12 11  7 6 5 4 3   0
+-----+----+--------+--+-----+-----+-----+---+--+-----+
| cond|000 | opcode | S| Rn  | Rd  |shamt|sh |0 | Rm  |
+-----+----+--------+--+-----+-----+-----+---+--+-----+

Data-processing immediate form  (type=001)
 31  28 27 25 24    21 20 19  16 15 12 11  8 7        0
+-----+----+--------+--+-----+-----+-----+-----------+
| cond|001 | opcode | S| Rn  | Rd  | rot |    imm8   |
+-----+----+--------+--+-----+-----+-----+-----------+

Load / Store immediate offset  (type=010)
 31  28 27 25 24 23 22 21 20 19  16 15 12 11                     0
+-----+----+--+--+--+--+--+-----+-----+-----------------------+
| cond|010 | P| U| B| W| L| Rn  | Rd  |        imm12          |
+-----+----+--+--+--+--+--+-----+-----+-----------------------+

Branch / Branch-with-Link  (type=101)
 31  28 27 25 24 23                                       0
+-----+----+--+----------------------------------------+
| cond|101 | L|              signed_imm24              |
+-----+----+--+----------------------------------------+
        target = PC + 8 + (sext(imm24) << 2)
```

### Condition codes (instr[31:28])

| Cond | Name | Predicate             |
|------|------|-----------------------|
| 0    | EQ   | Z=1                   |
| 1    | NE   | Z=0                   |
| 2    | CS/HS| C=1                   |
| 3    | CC/LO| C=0                   |
| 4    | MI   | N=1                   |
| 5    | PL   | N=0                   |
| 6    | VS   | V=1                   |
| 7    | VC   | V=0                   |
| 8    | HI   | C=1 & Z=0             |
| 9    | LS   | C=0 \| Z=1            |
| A    | GE   | N=V                   |
| B    | LT   | N!=V                  |
| C    | GT   | Z=0 & N=V             |
| D    | LE   | Z=1 \| N!=V           |
| E    | AL   | always                |
| F    | NV   | never (reserved)      |

### Data-processing opcodes (instr[24:21])

| Op | Name | Effect (when S=1, also sets NZCV) |
|----|------|------------------------------------|
| 0  | AND  | `Rd = Rn & Op2`                   |
| 1  | EOR  | `Rd = Rn ^ Op2`                   |
| 2  | SUB  | `Rd = Rn - Op2`                   |
| 3  | RSB  | `Rd = Op2 - Rn`                   |
| 4  | ADD  | `Rd = Rn + Op2`                   |
| 5  | ADC  | `Rd = Rn + Op2 + C`               |
| 6  | SBC  | `Rd = Rn - Op2 - !C`              |
| 7  | RSC  | `Rd = Op2 - Rn - !C`              |
| 8  | TST  | `flags = Rn & Op2`  (no WB)       |
| 9  | TEQ  | `flags = Rn ^ Op2`  (no WB)       |
| A  | CMP  | `flags = Rn - Op2`  (no WB)       |
| B  | CMN  | `flags = Rn + Op2`  (no WB)       |
| C  | ORR  | `Rd = Rn \| Op2`                  |
| D  | MOV  | `Rd = Op2`         (Rn ignored)   |
| E  | BIC  | `Rd = Rn & ~Op2`                  |
| F  | MVN  | `Rd = ~Op2`                       |

### Shift types (register-form Op2, instr[6:5])

| Code | Name | Effect                  |
|------|------|--------------------------|
| 00   | LSL  | `Rm << shamt`            |
| 01   | LSR  | `Rm >> shamt` (logical)  |
| 10   | ASR  | `Rm >>> shamt` (arith)   |
| 11   | ROR  | rotate right by shamt    |

### Load/Store flag bits

| Bit | Name | Meaning                                                   |
|-----|------|-----------------------------------------------------------|
| P   | 24   | pre/post-index (1 = add offset before access)             |
| U   | 23   | add (1) or subtract (0) the offset                        |
| B   | 22   | byte (1) or word (0) access                               |
| W   | 21   | writeback updated address to Rn                           |
| L   | 20   | load (1) or store (0)                                     |

armlite32 currently implements **word + pre-indexed + non-writeback** by
default; the other modes are reserved encodings.

---

## Comparative observations

1. **Encoding width tracks how much you want to express in one instruction.**
   scp16 fits a useful 9-instruction ISA in 16 bits by giving up the third
   register operand. armlite32 spends 32 bits but gets back the third
   operand, a barrel shifter, AND a 4-bit conditional &mdash; all in one
   instruction.

2. **Condition flags vs predicated execution are duals.** x86lite32 has flags
   + conditional jumps; armlite32 has flags + conditional execution on
   *every* instruction. The same idea applied at different granularity.

3. **Stack discipline costs control signals.** x86lite32's `PUSH/POP/CALL/RET`
   need a dedicated `esp_we` side-port on the regfile and three muxes in the
   memory subsystem. armlite32 doesn't have stack instructions per se &mdash;
   you express PUSH as `STR Rn, [SP, #-4]!` with writeback. RISC discipline
   forces you to build big things from small primitives.

4. **scp16's `JMP` field is 12 bits.** Real MIPS uses 26 bits for J-type; real
   ARM B uses 24 bits; real x86 has 8 / 16 / 32-bit branch displacement
   variants. **Wider branch fields buy you bigger functions.**

5. **scp16 has no flags register at all.** Branches read register values
   directly. This is the simplest possible scheme. The cost is that you can
   only compare two registers, never the result of a computation. (Try
   writing `if (a + b) goto X;` in scp16 &mdash; you can't, you need an
   explicit ADD first.) Flags amortise comparisons across instructions.
