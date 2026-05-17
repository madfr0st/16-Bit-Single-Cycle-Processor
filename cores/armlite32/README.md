# armlite32 &mdash; a 32-bit ARM-flavoured single-cycle CPU

> Honest scope: this is **not** an ARM CPU. The ARM ISA is a registered
> trademark and a licensed product of Arm Ltd. This is a 32-bit teaching CPU
> that implements a *subset of an ARMv4-style instruction encoding* so that
> the design philosophy is identical &mdash; conditional execution on every
> instruction, fixed 32-bit opcodes, load/store architecture, three-operand
> data processing, R15=PC, R14=LR, R13=SP, and the famous "barrel shifter for
> free" inside data-processing instructions.
>
> No ARM Holdings IP is used.

## What it implements

- **32-bit** fixed instruction width
- **16 GPRs** (`R0..R15`), with `R13=SP`, `R14=LR`, `R15=PC`
- **CPSR** flags: `N`, `Z`, `C`, `V`
- **Conditional execution** on every instruction (16 condition codes)
- **3-operand** data processing: `op Rd, Rn, <Operand2>`
- **Operand2** can be `Rm` shifted by `LSL/LSR/ASR/ROR` (immediate or
  register-form), or an 8-bit immediate rotated right by `2*rot`
- **Load/store-only** memory access (`LDR`, `STR` with `[Rn, #imm12]`)
- **Branch** (`B`) and **Branch-with-Link** (`BL`)
- 16 data-processing opcodes: `AND, EOR, SUB, RSB, ADD, ADC, SBC, RSC, TST,
  TEQ, CMP, CMN, ORR, MOV, BIC, MVN`

## Instruction formats

### Data-processing register form  (`type=000`)

```
 31  28 27 25 24    21 20 19  16 15 12 11  7 6 5 4 3   0
+-----+----+--------+--+-----+-----+-----+---+--+-----+
| cond|000 | opcode | S| Rn  | Rd  |shamt|sh |0 | Rm  |
+-----+----+--------+--+-----+-----+-----+---+--+-----+
```

### Data-processing immediate form  (`type=001`)

```
 31  28 27 25 24    21 20 19  16 15 12 11  8 7        0
+-----+----+--------+--+-----+-----+-----+-----------+
| cond|001 | opcode | S| Rn  | Rd  | rot |    imm8   |
+-----+----+--------+--+-----+-----+-----+-----------+
```

### Load/Store immediate offset  (`type=010`)

```
 31  28 27 25 24 23 22 21 20 19  16 15 12 11                     0
+-----+----+--+--+--+--+--+-----+-----+-----------------------+
| cond|010 | P| U| B| W| L| Rn  | Rd  |        imm12          |
+-----+----+--+--+--+--+--+-----+-----+-----------------------+
                                      ^                       ^
                                      L=1 LDR, L=0 STR; U=1 add, U=0 sub
```

### Branch / Branch-with-Link  (`type=101`)

```
 31  28 27 25 24 23                                       0
+-----+----+--+----------------------------------------+
| cond|101 | L|              signed_imm24              |
+-----+----+--+----------------------------------------+
                  branch target = PC + 8 + sext(imm24) << 2
```

## Condition codes (instr[31:28])

| Cond | Name | Predicate                            |
|------|------|--------------------------------------|
| 0    | EQ   | `Z=1`                                |
| 1    | NE   | `Z=0`                                |
| 2    | CS/HS| `C=1`           (unsigned >=)        |
| 3    | CC/LO| `C=0`           (unsigned <)         |
| 4    | MI   | `N=1`                                |
| 5    | PL   | `N=0`                                |
| 6    | VS   | `V=1`                                |
| 7    | VC   | `V=0`                                |
| 8    | HI   | `C=1 & Z=0`     (unsigned >)         |
| 9    | LS   | `C=0 | Z=1`     (unsigned <=)        |
| A    | GE   | `N=V`           (signed >=)          |
| B    | LT   | `N!=V`          (signed <)           |
| C    | GT   | `Z=0 & N=V`     (signed >)           |
| D    | LE   | `Z=1 | N!=V`    (signed <=)          |
| E    | AL   | always                               |
| F    | NV   | never (reserved in ARMv4)            |

## Demo program

```
        MOV  R1, #1                ; counter
        MOV  R2, #0                ; accumulator
        MOV  R3, #10               ; limit
loop:   ADD  R2, R2, R1
        ADD  R1, R1, #1
        CMP  R1, R3
        BLE  loop                  ; while (R1 <= R3)
end:    B    end                   ; "halt"
```

After the loop, `R2 = 1 + 2 + ... + 10 = 55`.

## Run it

```bash
iverilog -g2012 -I cores/armlite32/rtl \
    -o build_sim/armlite32.vvp \
    cores/armlite32/sim/cpu_tb.v cores/armlite32/rtl/*.v
vvp build_sim/armlite32.vvp
```

Watch for the final `Final R2 = 55 (expect 55)` line.

## Files

```
armlite32/
├── rtl/
│   ├── defines.v             cond codes, opcodes, shift types, reg consts
│   ├── cpu.v                 top
│   ├── program_counter.v     PC with branch + R15-write + +4 priority
│   ├── instruction_memory.v  ROM (with helper functions hand-assembling demo)
│   ├── control_unit.v        instruction-type decoder
│   ├── cond_unit.v           ARM's signature: 4-bit cond -> execute?
│   ├── register_file.v       16x32-bit GPRs with R15<-PC mirror
│   ├── barrel_shifter.v      Operand2 generator (LSL/LSR/ASR/ROR + ROR-imm)
│   ├── alu.v                 16-op ALU with NZCV semantics
│   ├── cpsr_reg.v            CPSR flag register
│   └── data_memory.v         word RAM
└── sim/
    └── cpu_tb.v              behavioural testbench
```

## What this teaches that the others don't

- **Conditional execution** on every instruction &mdash; the most ARM-specific
  feature. You get the if/else for free when the branch would otherwise be
  expensive.
- **Three-operand RISC** &mdash; cleaner than x86lite32's two-operand model,
  but at the cost of more bits per instruction.
- **Free barrel shift inside ALU op** &mdash; one of ARM's hallmark IPC tricks.
  `ADD R0, R1, R2, LSL #3` is a single-cycle "multiply by 8 then add".
- **Load/store architecture** &mdash; the central RISC discipline; you must
  bring data into registers before operating on it.
- **PC-as-a-general-register** &mdash; `MOV PC, LR` is a function return,
  `ADD PC, PC, #offset` is an indirect jump table. Powerful and footgun-rich.
