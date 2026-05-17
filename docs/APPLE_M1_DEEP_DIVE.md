# Apple M1 Deep Dive

> A guided tour of the Apple M1 SoC: the chip that, on its 2020 launch,
> shocked the industry by delivering single-threaded performance
> competitive with the best Intel/AMD x86 cores at a fraction of the
> power. This document focuses on its CPU complex (Firestorm P-core +
> Icestorm E-core), with shorter notes on the GPU, NPU, Unified Memory
> Architecture, AMX, and Fabric.
>
> Sources: Apple's public WWDC and event slides; Andrei Frumusanu's
> seminal Anandtech deep-dive (2020); reverse-engineering work by the
> Asahi Linux project (Marcan, Lina); Wikipedia / public patent filings;
> ChipsAndCheese and Travis Downs analyses. **No proprietary information.**

---

## Table of contents

1. [The shape of the chip](#the-shape-of-the-chip)
2. [Firestorm &mdash; the performance core](#firestorm--the-performance-core)
3. [Icestorm &mdash; the efficiency core](#icestorm--the-efficiency-core)
4. [Why the M1 surprised everyone](#why-the-m1-surprised-everyone)
5. [The ARMv8 ISA &mdash; why it helps](#the-armv8-isa--why-it-helps)
6. [Unified Memory Architecture](#unified-memory-architecture)
7. [The SoC fabric and last-level cache](#the-soc-fabric-and-last-level-cache)
8. [AMX &mdash; Apple's secret matrix engine](#amx--apples-secret-matrix-engine)
9. [GPU, Neural Engine, media](#gpu-neural-engine-media)
10. [Power and thermal](#power-and-thermal)
11. [How M1 compares to "your" SCP](#how-m1-compares-to-your-scp)
12. [Further reading](#further-reading)

---

## The shape of the chip

The original M1 (5 nm TSMC N5, 16 billion transistors, late 2020):

```
+-------------------------------------------------------------------+
|                                                                   |
|  +------+ +------+ +------+ +------+     +------+ +------+ +-+ +-+ |
|  |  F0  | |  F1  | |  F2  | |  F3  |     | I0   | | I1   | | | | | |
|  |Fire- | |Fire- | |Fire- | |Fire- |     |Ice   | |Ice   | |I| |I| |
|  |storm | |storm | |storm | |storm |     |storm | |storm | |2| |3| |
|  +------+ +------+ +------+ +------+     +------+ +------+ +-+ +-+ |
|     |        |        |        |            |        |       |  |  |
|     +---+----+---+----+---+----+            +---+----+--+----+--+  |
|         |        |        |                     |       (E cluster L2)  |
|  +------+--+ +---+----+ +-+------+  ...     +----+-----+               |
|  |L2 slice | |L2 slice| |L2 slice|          | E-cluster|               |
|  +---------+ +--------+ +--------+          |    L2    |               |
|       (private per P-core, ~12 MB total)    +----------+               |
|                                                                       |
|  +-----------------------------------------------------------------+   |
|  |                       SLC (System-Level Cache)                  |   |
|  |                ~8-16 MB depending on SKU, shared                |   |
|  +-----------------------------------------------------------------+   |
|                                                                       |
|  +-----+   +-----+   +-----+   +-----+   +---------+  +---------+     |
|  | LPDDR4X 128b channels   |  ANE (16-core NPU) |  Media engines     |
|  +-----+   +-----+         |                    |  ProRes / HEVC      |
|                                                                       |
|  +-----------------------------------------------------------------+   |
|  |    GPU (7- or 8-core, each ~128 ALUs, TBDR architecture)        |   |
|  +-----------------------------------------------------------------+   |
|                                                                       |
+-----------------------------------------------------------------------+
```

Approximate die budget:

- **4 Firestorm P-cores** (huge OoO)
- **4 Icestorm E-cores** (in-order-ish)
- **System-Level Cache (SLC)** of ~8-16 MB, accessible by **every** IP
  block (CPU, GPU, NPU, media) - unusual for the industry.
- **LPDDR4X-4266** on-package memory (typically 8/16 GB), exposing
  ~68 GB/s.
- **7- or 8-core Apple GPU** (TBDR, in the PowerVR lineage with major
  Apple-specific extensions).
- **16-core Neural Engine (ANE)** &mdash; ~11 TOPS INT8.
- **Media engines** for HEVC / H.264 / ProRes encode/decode in hardware.

---

## Firestorm &mdash; the performance core

The Firestorm core was, at launch, **the widest mainstream CPU front end
ever shipped**: an 8-instruction-wide decoder with sustained 6-7 IPC on
SPECint, hooked to an out-of-order back end with a **~630-entry reorder
buffer**.

```
                        +----------------------+
                        |  Branch Predictor    |     (very large,
                        |  + BTB               |      multi-level, TAGE-like)
                        +-----+----------------+
                              | predicted PC
                              v
            +-----------------------------+        +------------------+
            |    L1 Instruction Cache     |        | Instruction TLB  |
            |    192 KB, 6-way (!)        |--------|   192 entry      |
            +--------+----------+---------+        +------------------+
                     |
                     v
            +---------------------------------------+
            |          Decoders (8 wide)            |
            |   AArch64 fixed 4B instructions       |
            +---------------+-----------------------+
                            |
                            v
            +---------------------------------+
            |     Allocate / Rename            |
            |     (~8-wide; physical regs:     |
            |      ~354 INT, ~384 VEC)         |
            +--------------+-------------------+
                           |
                           v
            +---------------------------------+
            |     Reorder Buffer (~630)       |
            +--------------+------------------+
                           |
       +----------+--------+-------+----------+-----------+
       |          |                |          |           |
       v          v                v          v           v
  +--------+ +--------+      +-----------+ +-------+ +---------+
  | INT    | | INT    |      | LD/ST     | | FP/   | |  Branch |
  | sched  | | sched  |      | scheduler | | Vec   | |  sched  |
  +---+----+ +---+----+      +-----+-----+ +---+---+ +----+----+
      |          |                 |           |          |
      v          v                 v           v          v
  6 INT ALUs (incl. multi/div) + 2 LDs/cy + 1 ST/cy + 4 NEON 128b lanes
                                                       + dedicated branch unit
                                                       + AMX coprocessor
                                                         (matrix tiles)
```

Highlights worth dwelling on:

- **8-wide decode** &mdash; possible because **AArch64 is fixed-4-byte**.
  Decoding lane *N* is independent of lane *N-1* &mdash; trivially
  parallel. Try this with x86 (1..15 byte variable-length) and you have
  to do speculative length-decode trees; Apple sidestepped that whole
  problem by ISA choice.

- **192 KB L1I, 128 KB L1D** &mdash; massive, way bigger than what x86
  cores had at the time (32 KB / 32-48 KB). The cost is access latency;
  Apple pays it (~4-cycle L1D), but the hit rate dividend is enormous.

- **ROB ~630 entries** &mdash; bigger than any contemporary x86 core
  (Sunny Cove ~352, Zen 3 ~256). This is "more in-flight instructions",
  which directly converts to "more memory-level parallelism".

- **Six integer ALUs** &mdash; sustained 6-IPC integer is realistic on
  this core. Even Intel's wide P-cores struggle past 4.

- **Two load + one store per cycle** &mdash; sufficient for nearly all
  workloads.

- **NEON 4x 128-bit lanes** &mdash; not as wide as AVX-512, but four lanes
  of 128-bit FMA is 32 SP flops per cycle, very competitive.

- **Frequency ~3.2 GHz** &mdash; remarkably modest. Apple traded clock
  for width; they win the *integral* of "instructions per Joule".

### Memory hierarchy (Firestorm)

- L1I: 192 KB, 6-way, ~3-cycle.
- L1D: 128 KB, 8-way, ~4-cycle, 2 loads + 1 store per cycle.
- L2: 12 MB *shared by all four P-cores* in the cluster. 16-MB on M1 Pro
  ("Avalanche" version), 24-MB on M1 Max. ~16-cycle access.
- SLC: ~8-16 MB, sliced, accessible by **every** IP block; ~50-cycle.
- DRAM: LPDDR4X-4266, on-package; ~100 ns.

---

## Icestorm &mdash; the efficiency core

E-cores in the M1 are not the in-order toys of typical mobile chips.
Icestorm is a modest out-of-order machine that delivers something like
**1/3 of Firestorm's performance at 1/10 of the power**.

| Axis            | Icestorm                |
|-----------------|-------------------------|
| Decode width    | 3 wide                  |
| ROB             | ~120                    |
| Integer ALUs    | 3                       |
| Loads/Stores    | 1/1 per cycle           |
| NEON lanes      | 2x 128-bit              |
| L1I             | 128 KB                  |
| L1D             | 64 KB                   |
| L2              | 4 MB shared by 4 E-cores|
| Freq            | ~2.0 GHz                |
| Power           | ~ a few hundred mW      |

The point of Icestorm is to handle *steady-state* background work
(notifications, media keep-alives, scrolling at idle) while keeping the
Firestorms at near-zero power. macOS's scheduler explicitly assigns
"background" QoS classes to Icestorm.

---

## Why the M1 surprised everyone

Three things, plus one meta-thing.

1. **Width**. An 8-wide front-end Firestorm could simply *do more per
   cycle* than any contemporary 4-6-wide x86 P-core. Apple cashed in
   ISA-fixed-width to buy decode lanes.

2. **Cache, cache, cache**. 192 KB L1I + 128 KB L1D + 12 MB L2 + ~8 MB
   SLC, all on-die, all close, all shared via UMA. Memory accesses that
   would have missed L1 on Intel hit L1 here.

3. **Power discipline**. Apple's process (TSMC N5) was a node ahead of
   Intel 10-nm-equivalent at the time. Combine that with conservative
   clocks (~3.2 GHz vs Intel's 5 GHz) and you sit on the sweet spot of
   the V/F curve. Energy per instruction is dramatically lower.

4. (Meta) **Vertical integration**. Apple owns the ISA, the CPU
   microarchitecture, the SoC, the OS scheduler, the compiler, the
   firmware, and the application platform. They can co-design across
   every layer. Nobody else in PCs has this.

---

## The ARMv8 ISA &mdash; why it helps

The Firestorm core implements AArch64 (ARMv8.5-A at launch; later cores
bumped this). Compared to x86-64:

- **Fixed 4-byte instructions** &mdash; trivial parallel decode.
- **32 general-purpose registers** (vs x86's 16) &mdash; fewer register
  spills, less stack traffic.
- **3-operand instructions** (Rd, Rn, Rm) &mdash; no false dependencies on
  the destination.
- **No condition flags on most instructions** by default (vs x86's
  flags-set-on-everything model) &mdash; fewer false serialization
  points.
- **Load-linked / store-conditional + LSE atomics** &mdash; cleaner
  synchronization primitives than x86's LOCK-prefix model.
- **Weaker memory model** (acquire/release semantics, not TSO) &mdash;
  enables more reordering in hardware.
- **No partial-register stalls** &mdash; AArch64 cleanly zero-extends.
- **PAC (Pointer Authentication)** &mdash; hardware-checked pointers as a
  ROP defence. Apple uses this aggressively.
- **MTE (Memory Tagging Extension)** in later cores &mdash; per-allocation
  4-bit tags for use-after-free detection.

Every one of those bullets shrinks the implementation cost or removes a
performance hazard that x86 architects spend transistors and verification
cycles fighting.

---

## Unified Memory Architecture

Traditional PCs have separate physical memory pools for CPU and GPU; data
has to be **copied** across the PCIe bus to be visible to the other. M1
puts everything in one address space, attached to one physical memory
pool, with **every** IP block (CPU cluster, GPU, NPU, media engines)
treating that pool as its own.

Benefits:

- Zero-copy CPU<->GPU sharing of buffers. Massive win for graphics,
  video editing, ML.
- One memory controller serving the whole chip => uniform programming
  model.
- Higher effective bandwidth utilisation (no bus arbitration overhead).

Drawbacks:

- Memory is **on-package**, soldered, non-upgradeable.
- Capacity is limited by what can fit alongside the SoC die (8/16 GB on
  M1; later M-series goes higher).

---

## The SoC fabric and last-level cache

Apple connects everything with a high-bandwidth **fabric** (the public
name is "AMBA-style", but it's heavily Apple-customised). The **SLC** is
a coherent last-level cache shared by all IP blocks; the GPU benefits
nearly as much as the CPU, which is unusual.

Coherence between CPU clusters and the GPU is handled in the fabric;
software sees a single coherent address space.

---

## AMX &mdash; Apple's secret matrix engine

AMX (Apple Matrix Extensions, not to be confused with Intel's AMX) is an
**undocumented coprocessor** attached to each Firestorm cluster. It
executes matrix-multiply instructions with **1 KB tile** registers and
gets reverse-engineered numbers like 1 TFLOPS FP32 per AMX block on M1.
Apple does not expose AMX in the public AArch64 ISA; instead, the
Accelerate framework (BLAS, BNNS) emits it under the hood. Linear algebra
on Apple Silicon often hits AMX without programmers knowing.

Later M-series chips (M3, M4) added official `SME` (Scalable Matrix
Extension) which is the ARM-standard analogue, in addition to AMX.

---

## GPU, Neural Engine, media

- **GPU (7- or 8-core)**: each "core" is ~128 ALUs (FP32-ish), TBDR
  (tile-based deferred rendering) architecture. ~2.6 TFLOPS FP32 on M1.
  Uses *unified memory* with the CPU.
- **Neural Engine (ANE)**: 16 specialized cores, ~11 TOPS INT8 on M1.
  Targeted at CoreML model execution. Software stack opaque.
- **Media engines**: dedicated hardware for HEVC, H.264, ProRes (on
  Pro/Max/Ultra) encode + decode. Drives most of the M-series Mac's
  insanely-good battery life during video playback.

---

## Power and thermal

Firestorm typical power: ~5 W single-core sustained. Icestorm typical:
~few hundred mW. The whole M1 SoC under sustained desktop workload pulls
~15-25 W. **An entire MacBook Air with no fan runs the whole chip flat
out**.

The energy efficiency comes from (a) advanced node, (b) modest clocks,
(c) wide microarchitecture (more parallelism = fewer Joules per
instruction), (d) aggressive power gating and DVFS.

---

## How M1 compares to "your" SCP

| Axis                       | scp16          | armlite32         | Firestorm (M1 P-core)   |
|----------------------------|----------------|-------------------|--------------------------|
| Width                      | 1              | 1                 | 8 (decode), 6+ (back end)|
| Cycles per instr           | 1              | 1                 | ~0.15-0.20 (steady)      |
| In-flight uops             | 1              | 1                 | ~630                     |
| Architectural registers    | 16             | 16                | 32 GPR + 32 NEON (V0-V31)|
| Physical registers (rename)| n/a            | n/a               | ~354 INT + ~384 vec      |
| L1I / L1D                  | 0              | 0                 | 192 KB / 128 KB          |
| L2 / L3                    | 0              | 0                 | 12 MB / 8-16 MB SLC      |
| Branch predictor           | none           | none              | multi-level TAGE-class   |
| Power                      | <1 W           | <1 W              | ~5 W per core            |
| Frequency                  | ~50-100 MHz    | ~50-100 MHz       | 3.2 GHz                  |
| Process node               | 28-nm-ish FPGA | 28-nm-ish FPGA    | TSMC N5                  |
| Transistors                | ~thousands     | ~tens of thousands| ~3 billion per P-core    |

What lives in the gap? Roughly the same set of additions as for Intel:
pipelining, branch prediction, caches, virtual memory, multiple issue,
register renaming, ROB, out-of-order scheduling, store buffer, SIMD
lanes, microcode for complex bits, coherence, mitigations. The path from
`armlite32` to Firestorm is exactly the same conceptual journey as from
`x86lite32` to Lion Cove &mdash; just with different micro-decisions at
each fork.

---

## Further reading

- **Andrei Frumusanu, Anandtech**, *The 2020 Apple M1: A Detailed Look*.
  Still the most thorough public deep dive on Firestorm.
- **Asahi Linux Project** (Hector "marcan" Martin, Alyssa Rosenzweig,
  Asahi Lina) &mdash; the people who reverse-engineered Apple Silicon to
  port Linux. Their blogs document the SoC fabric, GPU, ANE, etc.
- **ARM AArch64 Architecture Reference Manual** &mdash; the ISA Apple
  implements (plus Apple-specific extensions).
- **Apple WWDC 2020-2024** &mdash; Apple's own public-facing material on
  M-series.
- Travis Downs's blog &mdash; microbenchmark deep dives that often
  compare M1 against contemporary x86.
- Hennessy & Patterson, *Computer Architecture: A Quantitative Approach*
  &mdash; section on "wide superscalar" is conceptually Firestorm.
