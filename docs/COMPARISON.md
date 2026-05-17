# Seven Processors, Side By Side

This doc lays the four teaching cores in this repo next to the three real
production cores (Intel P-core, Apple M1 P-core, NVIDIA Hopper SM) on
every axis that can be measured. Read top-to-bottom to see exactly how
complexity scales from "I can build this in a weekend" to "this is the
result of 25 years of work by hundreds of engineers".

---

## Axis 1: ISA and instruction encoding

|                      | scp16             | x86lite32           | armlite32              | Intel Lion Cove (x86-64)        | Apple Firestorm (AArch64)        |
|----------------------|-------------------|---------------------|------------------------|---------------------------------|----------------------------------|
| Word size            | 16                | 32                  | 32                     | 64 (also runs 32 / 16 modes)    | 64                               |
| Instruction width    | 16-bit fixed      | 32-bit fixed        | 32-bit fixed           | **1..15 bytes variable**        | 32-bit fixed                     |
| Architectural GPRs   | 16                | 16                  | 16 (R15=PC, R14=LR, R13=SP) | 16 GPR + RIP + flags        | 31 GPR + ZR + SP + PC + flags    |
| Vector / SIMD regs   | 0                 | 0                   | 0                      | 32 ZMM (512b) on server         | 32 V (128b NEON)                 |
| Number of opcodes    | 9                 | ~31                 | 16 DP + LDR/STR + B/BL | ~1300+ (with all extensions)    | ~1000 (incl NEON/SVE2)           |
| Condition flags      | none              | CF/ZF/SF/OF         | N/Z/C/V                | CF/ZF/SF/OF/PF/AF...            | N/Z/C/V (and predicates for SVE) |
| Predicated execution | no                | only branches       | **every instruction**  | only `CMOV`/`SETcc`/branches    | only `CSEL`/branches             |
| Stack discipline     | manual (no SP)    | PUSH/POP/CALL/RET   | LDR/STR + B/BL          | PUSH/POP/CALL/RET                | LDP/STP + BL/RET                 |

The single most-leveraged design decision in this whole table is
**"variable-length vs fixed-length instructions"**. Fixed-length =
parallel-decodable = cheap to build a wide front end. Variable-length =
denser code + legacy compatibility + an enormous decoder. Apple cashed in
fixed-length to buy 8-wide decode in Firestorm; Intel pays for
variable-length with the uop cache + MITE complexity.

---

## Axis 2: Microarchitecture

|                          | scp16     | x86lite32 | armlite32 | Lion Cove P-core | Firestorm P-core |
|--------------------------|-----------|-----------|-----------|------------------|------------------|
| Pipeline depth           | 1 (single-cycle) | 1  | 1  | ~15-20 stages    | ~15 stages       |
| Multiple issue (width)   | 1         | 1         | 1         | 8 (decode)       | 8 (decode)       |
| Out-of-order execution   | no        | no        | no        | yes              | yes              |
| Reorder buffer entries   | 0         | 0         | 0         | ~576             | ~630             |
| Physical INT regs        | n/a       | n/a       | n/a       | ~390             | ~354             |
| Physical vector regs     | n/a       | n/a       | n/a       | ~432             | ~384             |
| Reservation stations     | 0         | 0         | 0         | ~250+            | unified, large   |
| Branch predictor         | none      | none      | none      | TAGE + ITA + RAS | TAGE-like        |
| Speculation              | none      | none      | none      | yes (deep)       | yes (deep)       |
| Hardware prefetchers     | 0         | 0         | 0         | 4+               | several          |
| SMT (HT) threads/core    | 1         | 1         | 1         | 1-2              | 1                |

A *single instruction* taking one cycle (scp16) vs *eight instructions
per cycle, hundreds in flight, executed out of order* (Firestorm) is the
~50x raw IPC gap. Frequency adds another ~30-50x. Total ~1500-2500x
"per-thread performance" gap from scp16 to a modern flagship.

---

## Axis 3: Memory hierarchy

|                       | scp16              | x86lite32          | armlite32         | Lion Cove          | Firestorm          |
|-----------------------|--------------------|--------------------|-------------------|--------------------|--------------------|
| L1 I-cache            | none (ROM)         | none (ROM)         | none (ROM)        | 32 KB              | 192 KB             |
| L1 D-cache            | none (1 KB SRAM)   | none (4 KB SRAM)   | none (4 KB SRAM)  | 48 KB              | 128 KB             |
| L2                    | none               | none               | none              | 1.25-2 MB/core     | 12 MB shared/4cores|
| LLC / SLC             | none               | none               | none              | 3-30+ MB           | 8-16 MB shared     |
| TLBs / virtual memory | no                 | no                 | no                | yes (multi-level)  | yes (multi-level)  |
| Memory ordering model | n/a                | n/a                | n/a               | x86-TSO            | weak (acquire/release)|
| Memory bandwidth      | trivial            | trivial            | trivial           | ~80 GB/s (DDR5 x2) | ~68-400 GB/s (UMA) |
| Memory latency        | trivial            | trivial            | trivial           | ~80-110 ns         | ~100 ns            |

Caches don't add new *functionality*; they add **performance**. But they
add *huge* design complexity: coherence protocols (MESI/MOESI), replacement
policies, eviction, prefetching, virtual addressing, TLB shootdowns,
cache attacks (Spectre/Meltdown surface), QoS, etc.

---

## Axis 4: Numeric & SIMD

|                       | scp16  | x86lite32 | armlite32 | Lion Cove                | Firestorm        |
|-----------------------|--------|-----------|-----------|--------------------------|------------------|
| Native integer width  | 16     | 32        | 32        | 64                       | 64               |
| Floating-point        | no     | no        | no        | x87 + SSE/AVX (32/64)   | NEON FP (16/32/64)|
| Vector width          | 0      | 0         | 0         | 512 bits (AVX-512, server)| 128 bits (NEON)  |
| Vector lanes/cycle    | 0      | 0         | 0         | 2x 512b FMA              | 4x 128b FMA      |
| Peak FP32 GFLOPS/core | 0      | 0         | 0         | ~1024 @ 4 GHz            | ~410 @ 3.2 GHz   |
| Matrix accelerator    | no     | no        | no        | AMX (Sapphire Rapids+)   | AMX (Apple, undoc)|
| Crypto units          | no     | no        | no        | AES-NI, SHA-NI           | NEON AES/SHA     |

---

## Axis 5: Power & process

|                       | scp16            | x86lite32        | armlite32        | Lion Cove        | Firestorm         |
|-----------------------|------------------|------------------|------------------|------------------|-------------------|
| Implementation       | FPGA (28nm-ish) | FPGA (28nm-ish) | FPGA (28nm-ish)  | Intel 4 / TSMC N3| TSMC N5           |
| Frequency            | 50-100 MHz       | 50-100 MHz       | 50-100 MHz       | 5.0-6.2 GHz      | 3.2 GHz           |
| Power per core       | <1 W (FPGA load)| <1 W            | <1 W             | 25-100 W         | ~5 W              |
| Transistors per core | ~10 k LUTs      | ~30 k LUTs       | ~30 k LUTs       | ~10^9            | ~3 x 10^9         |
| Cores in flagship    | 1                | 1                | 1                | 8 P + 16 E       | 4 P + 4 E (M1); more on M-Max/M-Ultra |
| TDP                  | n/a             | n/a              | n/a              | 65-253 W         | 15-30 W (M1)      |

---

## Axis 6: Security / mitigations

| Feature                       | scp16 | x86lite32 | armlite32 | Lion Cove | Firestorm |
|-------------------------------|-------|-----------|-----------|-----------|-----------|
| Privilege rings / EL levels   | no    | no        | no        | 4 rings + VMX + SMM | EL0-3 + Secure World |
| MMU / page tables             | no    | no        | no        | 5-level paging | 4-level (16K granule) |
| ASLR-relevant entropy         | n/a   | n/a       | n/a       | yes       | yes       |
| ROP/JOP defences              | n/a   | n/a       | n/a       | CET (shadow stack + IBT) | PAC (pointer auth), BTI |
| Memory tagging                | no    | no        | no        | LAM (linear addr mask)   | MTE (later cores)        |
| Spectre/Meltdown mitigations  | n/a   | n/a       | n/a       | IBRS/STIBP/IBPB/SSBD/eIBRS/CSV | extensive (CSV2/3) |
| Side-channel hardening        | n/a   | n/a       | n/a       | hardware + microcode | hardware + firmware |

---

## Axis 7: "How would I evolve my SCP into one of these?"

A roadmap, in order, with the most painful step bolded:

1. Add a 5-stage pipeline (IF/ID/EX/MEM/WB). Adds hazard detection and
   forwarding. **+1 textbook chapter.**
2. Add caches (I, D) and a memory hierarchy. +2 chapters.
3. Add a branch predictor (start with 1-bit, end with TAGE). +1 chapter.
4. Add SIMD (a 128-bit data path next to the integer one). +1 chapter.
5. Add multiple-issue / superscalar dispatch. +1 chapter.
6. **Add register renaming + ROB + OoO scheduling. +3 chapters. THIS is
   the project that takes a person from "I can build a CPU" to "I am a
   CPU architect".**
7. Add cache coherence + multi-core (MESI/MOESI). +1 chapter.
8. Add virtual memory + TLB + privilege levels. +1 chapter.
9. Harden against side-channel attacks. +N chapters, ongoing.

That sequence is, with minor reordering, the literal history of x86 and
ARM mainstream CPUs from 1985 to today.

---

## One-paragraph TL;DR for each core

- **scp16** &mdash; a textbook chapter compiled to gates. Read it to
  understand the bones of every CPU.
- **x86lite32** &mdash; the CISC tax explained: condition flags, two-operand
  ops, stack-based subroutines. Decoder fan-out grows; pipeline parallelism
  gets harder.
- **armlite32** &mdash; the RISC discount explained: fixed widths,
  load/store, three-operand, free barrel shift, and the unusually elegant
  "every instruction is conditional".
- **Intel Lion Cove** &mdash; the apex of CISC + OoO. Pays the variable-
  length decoder tax with a uop cache, runs at huge clocks, eats the
  power, fields enormous caches and vector units. Wins on
  single-thread legacy throughput.
- **Apple Firestorm** &mdash; the apex of fixed-width-RISC + OoO. Spends
  the ISA simplicity on an 8-wide decode and a ~630-entry ROB, sits at
  3.2 GHz, eats 5W per core. Wins on performance/Watt and is
  competitive on raw single-thread.
- **gpulite32** &mdash; SIMT in 9 modules: one decoder broadcasts to 8
  lanes, each with its own register file and predicate. Demonstrates
  the throughput-over-latency design point.
- **NVIDIA Hopper SM** &mdash; the apex of SIMT throughput. 128 CUDA
  cores + 4 Tensor Cores per SM, 132 SMs per chip, ~270k threads
  on-chip simultaneously, ~2000 TFLOPS FP16 from Tensor Cores. Hides
  latency by massive multithreading instead of OoO speculation.

---

## Axis 8: Where the GPU sits on every axis

GPUs and CPUs optimise for fundamentally different points:

| Axis                | CPU goal              | GPU goal               |
|---------------------|------------------------|-------------------------|
| What it optimises   | latency of one thread | throughput of many     |
| How it hides memory | OoO speculation, caches| massive multithreading |
| Width of decode     | 4-8 (parallel decode) | 1 (broadcast to lanes) |
| Concurrency unit    | 1-8 threads (HT/SMT)  | thousands of threads   |
| Branch handling     | predict + recover     | predicate + serialize  |
| Programming model   | scalar (per thread)   | SIMT (per warp)        |

Side-by-side numbers:

|                                | gpulite32   | NVIDIA H100 SM      |
|--------------------------------|-------------|----------------------|
| Lanes per warp                  | 8           | 32                   |
| CUDA cores per SM               | 8           | 128                  |
| Tensor Cores per SM             | 0           | 4 (4th gen)          |
| Warp schedulers per SM          | 1           | 4                    |
| Max concurrent warps per SM     | 1           | 64                   |
| Per-thread registers            | 16          | up to 255            |
| Register file per SM            | 256 B       | 256 KB               |
| Shared memory per SM            | 4 KB        | up to 228 KB         |
| L1 / L2 caches                  | none        | yes / 50 MB chip     |
| Floating-point                  | none        | FP64/32/16/BF16/FP8  |
| Memory bandwidth                | trivial    | 3.35 TB/s HBM3       |
| Process node                    | FPGA 28-nm | TSMC 4N (custom 5 nm)|
| Transistors                     | ~50k LUTs   | 80 billion           |
| TDP                             | <1 W       | 700 W                |
| Peak FP16 TFLOPS                | 0           | 1979 (Tensor Cores)  |

The factor between gpulite32 and a single H100 SM, on most useful axes,
is **about 100x to 1,000,000x**. And an H100 has 132 SMs.
