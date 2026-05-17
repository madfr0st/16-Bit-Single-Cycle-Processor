# gpulite32 &mdash; a 32-bit NVIDIA-flavoured single-cycle GPU

> Honest scope: this is **not** a real NVIDIA GPU. A modern NVIDIA flagship
> (Hopper H100, Blackwell B200) is the result of tens of thousands of
> engineer-years, has ~80 billion transistors, runs the proprietary SASS
> binary ISA and a vast software stack (CUDA, cuDNN, NCCL, NVLink, Tensor
> Cores, RT Cores, Multi-Instance GPU, ...). Even the "tiny" RT 4060 is
> three orders of magnitude beyond what's reasonable to build for teaching.
>
> What this core **does** is implement the *SIMT (Single Instruction Multiple
> Threads) execution model* that defines all modern GPUs: one instruction
> stream broadcast to many lanes, each lane with its own register state,
> per-lane predicates for divergence. Once you understand this skeleton,
> everything in NVIDIA's whitepapers makes sense.

## What it implements

- **1 Streaming Multiprocessor (SM)** with 1 warp scheduler
- **Warp size = 8** (real NVIDIA = 32; shrunk here for sim manageability)
- **8 SIMT integer lanes** (1 "CUDA core" each)
- Per-lane **16 x 32-bit register file**
- Per-lane **4-bit predicate register** (P0..P3) for divergence
- Per-lane **integer ALU** (ADD, SUB, MUL, AND, OR, XOR, SHL, SHR)
- **Predicated execution** on every instruction (the *defining* SIMT feature)
- **Special registers**: `%tid.x` (lane id), `%ntid.x` (warp size)
- **Global memory** (16 KB, 8-port write/read for SIMT-style coalesced access)
- **Shared memory** (4 KB, single-port abstraction)
- Branches, BAR.SYNC (no-op with 1 warp), EXIT (halt the warp)
- PTX-inspired ISA with conventional NVIDIA mnemonics

## What real NVIDIA SMs have that this design doesn't

| Feature                               | Real Hopper SM | gpulite32  |
|----------------------------------------|----------------|------------|
| Warp size                              | 32             | 8          |
| CUDA cores per SM                      | 128            | 8          |
| Tensor Cores per SM                    | 4              | 0          |
| Warp schedulers per SM                 | 4              | 1          |
| Max concurrent warps per SM            | 64             | 1          |
| Per-thread registers                   | 255            | 16         |
| Register file per SM                   | 256 KB         | 256 B      |
| Shared memory per SM                   | 228 KB         | 4 KB       |
| L1 cache                               | yes            | no         |
| L2 cache                               | 50+ MB chip    | no         |
| FP32 / FP64 / FP16 / BF16 / INT8       | all            | INT32 only |
| Floating-point                         | yes            | no         |
| Convergence stack for divergence       | yes (ITS)      | simplified |
| Memory coalescing logic                | yes            | abstracted |
| Bank-conflict shared memory            | 32 banks       | none       |
| Async copy (TMA on Hopper)             | yes            | no         |
| RT Cores (ray tracing)                 | n/a            | n/a        |

The point isn't to match these; it's to make the *shape* familiar so the
real numbers don't surprise you.

## Instruction format

```
   31    27 26 25  23 22  19 18  15 14  11 10                        0
  +---------+--+-----+-----+-----+-----+---------------------------+
  |  opcode |!P| pi  | dst | src1| src2|     imm11 / offset        |
  +---------+--+-----+-----+-----+-----+---------------------------+
       5     1    3    4     4     4             11
```

- **opcode** (5 bits): one of 32 instructions (table below)
- **!P** (1 bit): negate the predicate (1 = run when pred is false)
- **pi** (3 bits): predicate index P0..P3; `pi=111` is the special
  "always-true" alias (`@p_true` in PTX)
- **dst / src1 / src2** (4 bits each): R0..R15
- **imm11** (11 bits): sign-extended to 32 (for `ADDI`, `BRA`, addr disp)

## Opcode table

| Op   | Mnemonic       | Effect (per lane, if predicate true)        |
|------|----------------|---------------------------------------------|
| 0x00 | MOV.RR         | `dst = src1`                                |
| 0x01 | MOV.RI         | `dst = sext(imm)`                           |
| 0x02 | S2R Rd,%tid.x  | `dst = lane_id`                             |
| 0x03 | S2R Rd,%ntid.x | `dst = WARP_SIZE`                           |
| 0x08 | ADD            | `dst = src1 + src2`                         |
| 0x09 | SUB            | `dst = src1 - src2`                         |
| 0x0A | MUL            | `dst = src1 * src2` (low 32 bits)           |
| 0x0B | AND            | `dst = src1 & src2`                         |
| 0x0C | OR             | `dst = src1 | src2`                         |
| 0x0D | XOR            | `dst = src1 ^ src2`                         |
| 0x0E | SHL            | `dst = src1 << src2[4:0]`                   |
| 0x0F | SHR            | `dst = src1 >> src2[4:0]`                   |
| 0x10 | ADDI           | `dst = src1 + sext(imm)`                    |
| 0x11 | MULI           | `dst = src1 * sext(imm)`                    |
| 0x14 | SETP.EQ        | `P[imm[1:0]] = (src1 == src2)`              |
| 0x15 | SETP.NE        | `P[imm[1:0]] = (src1 != src2)`              |
| 0x16 | SETP.LT        | `P[imm[1:0]] = (src1 < src2)`   signed      |
| 0x17 | SETP.LE        | `P[imm[1:0]] = (src1 <= src2)`              |
| 0x18 | SETP.GT        | `P[imm[1:0]] = (src1 > src2)`               |
| 0x19 | SETP.GE        | `P[imm[1:0]] = (src1 >= src2)`              |
| 0x1A | LD.GLOBAL      | `dst = GLOBAL[src1 + sext(imm)]`            |
| 0x1B | ST.GLOBAL      | `GLOBAL[src1 + sext(imm)] = dst`            |
| 0x1C | LD.SHARED      | `dst = SHARED[src1 + sext(imm)]`            |
| 0x1D | ST.SHARED      | `SHARED[src1 + sext(imm)] = dst`            |
| 0x1E | BRA            | `warp_PC += sext(imm) << 2` if any lane active|
| 0x1F | BAR.SYNC / EXIT| `imm[10]=1` -> EXIT; `imm[10]=0` -> BAR.SYNC|

## Demo program: a tiny paint kernel

The instruction memory ships with a hand-assembled "basic paint software"
kernel that treats the first 256 bytes of global memory as an 8x8
framebuffer (`pixel(row,col) = GLOBAL[(row*8 + col) * 4]`) and runs three
classic paint primitives:

1. **`clear_canvas(color=0)`** &mdash; each of the 8 lanes loops over rows
   0..7 and writes 0 into its own column. 8 lanes x 8 rows = 64 pixels
   cleared in 8 loop iterations.
2. **`draw_hline(row=3, color=0xAA)`** &mdash; one `ST.GLOBAL` in parallel:
   lane *i* writes color to pixel (3, *i*). **64 pixels of work in one
   cycle.** This is the magic of SIMT.
3. **`plot_pixel(5, 5, color=0xFF)`** &mdash; predicate-gated store. All 8
   lanes flow through the instruction (you pay the cycle either way) but
   only lane 5 retires the write. This is how an `if (tid == X)` block
   compiles on a GPU.

Pseudo-PTX:

```
        S2R     R0, %tid.x          ; R0 = column = tid
        MOV     R10, #1             ; constants live in registers
        MOV     R11, #2             ; (word -> byte shift)
        MOV     R12, #3             ; (col -> stride-of-8 shift)
        MOV     R8,  #8             ; loop limit

; ---- clear_canvas(0) -----------------------------------------------------
        MOV     R5,  #0             ; row = 0
clear:  SETP.GE P0, R5, R8
        @P0 BRA after_clear
        SHL     R2, R5, R12         ; row * 8
        ADD     R2, R2, R0          ; + col
        SHL     R2, R2, R11         ; * 4  (byte address)
        MOV     R1, #0
        ST.G    [R2+0], R1
        ADD     R5, R5, R10
        BRA     clear

; ---- draw_hline(3, 0xAA) -------------------------------------------------
after_clear:
        MOV     R5, #3
        SHL     R2, R5, R12
        ADD     R2, R2, R0
        SHL     R2, R2, R11
        MOV     R1, #170
        ST.G    [R2+0], R1          ; 8 lanes write 8 pixels in ONE cycle

; ---- plot_pixel(5, 5, 0xFF) ---------------------------------------------
        MOV     R3, #5
        SETP.EQ P1, R0, R3          ; P1 = (col == 5)
        MOV     R6, #5
        SHL     R2, R6, R12
        ADD     R2, R2, R3
        SHL     R2, R2, R11
        MOV     R1, #255
        @P1 ST.G [R2+0], R1         ; only lane 5 retires
        EXIT
```

Expected canvas after the kernel halts:

```
   .---- 8x8 framebuffer ----.
    col: 0   1   2   3   4   5   6   7
r=0 |    .   .   .   .   .   .   .   .
r=1 |    .   .   .   .   .   .   .   .
r=2 |    .   .   .   .   .   .   .   .
r=3 |   aa  aa  aa  aa  aa  aa  aa  aa     <-- hline
r=4 |    .   .   .   .   .   .   .   .
r=5 |    .   .   .   .   .  ff   .   .     <-- single pixel
r=6 |    .   .   .   .   .   .   .   .
r=7 |    .   .   .   .   .   .   .   .
   `------------------------'
```

## Run it

```bash
iverilog -g2012 -I cores/gpulite32/rtl \
    -o build_sim/gpulite32.vvp \
    cores/gpulite32/sim/gpu_tb.v cores/gpulite32/rtl/*.v
vvp build_sim/gpulite32.vvp
```

Watch the `Global memory contents` table at the end &mdash; it should
match the "expected" column.

## Files

```
gpulite32/
├── rtl/
│   ├── defines.v             opcodes, warp size, predicate aliases
│   ├── gpu.v                 top-level SM (PC + IM + decoder + 8 lanes + memories)
│   ├── warp_pc.v             single-warp program counter
│   ├── instruction_memory.v  ROM holding the kernel + hand-assembled demo
│   ├── control_unit.v        opcode -> control signal decoder
│   ├── lane.v                ONE SIMT lane: regs + predicates + ALU + mem ports
│   ├── alu.v                 per-lane integer ALU (the "CUDA core")
│   ├── shared_memory.v       on-SM scratchpad (NVIDIA "shared memory")
│   └── global_memory.v       off-SM 8-port RAM (HBM stand-in)
└── sim/
    └── gpu_tb.v              behavioural testbench
```

## What this teaches that the CPUs don't

- **SIMT is just one decoder broadcast to many lanes.** The decoder in
  `control_unit.v` is identical in structure to a CPU decoder; the only
  new thing is that 8 copies of `lane.v` consume its outputs in parallel.
- **Per-lane state is what makes the parallelism useful.** All 8 lanes
  read the SAME instruction, but each gets its own `tid` and its own
  register values, so they all do *useful different work*.
- **Predicates are how you do `if/else` on a SIMD machine.** When the
  predicate is false in some lanes, those lanes' writes are silently
  squashed for that cycle -- their hardware is wasted but their state
  stays consistent. This is the cost of "warp divergence".
- **Memory coalescing matters.** The demo program has each lane write to
  `tid*4`, which is 8 consecutive 32-bit words = 32 bytes = ONE cache
  line. A real GPU coalesces all 8 lanes' writes into a single memory
  transaction. Non-coalesced patterns (e.g., each lane writes to
  `tid*1024`) cost 8 transactions instead of 1.
- **You can't think about a GPU one thread at a time.** You have to think
  about *a warp at a time*. This is a programming-model shift, not a
  hardware shift.

## Where to go next

- Read [`../../docs/NVIDIA_DEEP_DIVE.md`](../../docs/NVIDIA_DEEP_DIVE.md)
  for the production version of every concept here.
- Try adding floating-point lanes alongside the integer lanes.
- Try implementing a *real* convergence stack for divergent branches,
  rather than the "branch if any lane true" simplification.
- Try multi-warp interleaving on a single SM: 4 warps round-robin'd
  through the decoder, each with its own PC and register file. That's
  the single biggest step toward real-GPU IPC.
