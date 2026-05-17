# Intel P-Core Deep Dive

> A guided tour of a modern Intel performance core (the "P-core" lineage:
> Sunny Cove -> Cypress Cove -> Golden Cove -> Raptor Cove -> Redwood
> Cove -> Lion Cove). This is what the `x86lite32` core in this repo
> *aspires* to be a 0.0001% caricature of. The differences explain why
> real CPUs took 50 years and tens of billions of dollars to build.
>
> All facts here come from publicly available material: Intel's
> Architecture Day decks, the Intel 64 / IA-32 Optimization Reference
> Manual, the Intel Software Developer's Manual, conference papers from
> Intel architects, and detailed third-party microarchitecture writeups
> (Anandtech, ChipsAndCheese, RealWorldTech).

---

## Table of contents

1. [What "Intel CPU" actually means](#what-intel-cpu-actually-means)
2. [Outside view &mdash; the SoC](#outside-view--the-soc)
3. [Core block diagram (Golden Cove / Raptor Cove)](#core-block-diagram)
4. [The front end](#the-front-end)
   - Branch predictor
   - L1I, ITLB, fetch
   - Legacy decoders, uop cache, MITE/DSB
   - Loop Stream Detector and the µop queue
   - Allocate / rename / retire
5. [The out-of-order engine](#the-out-of-order-engine)
   - Register renaming
   - Reorder Buffer (ROB)
   - Schedulers and dispatch ports
   - Execution units (integer, vector, AVX-512, memory)
6. [The memory subsystem](#the-memory-subsystem)
   - L1D, store buffer, load buffer
   - L2, L3, ring or mesh interconnect
   - Hardware prefetchers
7. [Vector and matrix extensions](#vector-and-matrix-extensions)
   - SSE / AVX / AVX2 / AVX-512 / AMX
8. [Hyper-Threading (SMT)](#hyper-threading-smt)
9. [P-core vs E-core (Alder Lake on)](#p-core-vs-e-core-alder-lake-on)
10. [Security mitigations](#security-mitigations)
11. [Performance numbers, roughly](#performance-numbers-roughly)
12. [How "your" SCP would have to grow to become this](#how-your-scp-would-have-to-grow)

---

## What "Intel CPU" actually means

"An Intel CPU" today is a heterogeneous *system on chip*: multiple
performance cores ("P-cores"), multiple efficiency cores ("E-cores", since
Alder Lake), an integrated graphics block, a memory controller, a system
agent, last-level cache, plus PCIe, USB, and platform glue. We focus on the
P-core because that's where the microarchitectural fireworks live.

A modern Intel P-core is **deeply out-of-order, ~8-wide on the front end,
~12-wide on the back end, has hundreds of in-flight instructions, executes
512-bit SIMD natively, runs at 5+ GHz, and burns 30-100W per core under
load**. Compare to scp16: 1-wide, no out-of-order, no parallelism, no SIMD,
maybe 100 MHz on a small FPGA. Six orders of magnitude on most axes.

---

## Outside view &mdash; the SoC

A Raptor Lake-S desktop die looks roughly like this:

```
+----------------------------------------------------------------------+
|                                                                      |
|   +------+ +------+ +------+ +------+    +-------------------+       |
|   | P0   | | P1   | | P2   | | P3   |    |  iGPU (Xe-LP)    |       |
|   | core | | core | | core | | core |    +-------------------+       |
|   +--+---+ +--+---+ +--+---+ +--+---+                                |
|      |        |        |        |                                    |
|   +--+--------+--------+--------+----- RING BUS (or mesh) -----+     |
|   |                                                            |     |
|   |   +--------+ +--------+   +-------+ +-------+              |     |
|   |   | LLC s0 | | LLC s1 |   | LLC s2| | LLC s3| ...          |     |
|   |   +--------+ +--------+   +-------+ +-------+              |     |
|   |                                                            |     |
|   |   +------------------+   +-----------------+               |     |
|   |   | E-core cluster x4| ..| E-core cluster  |               |     |
|   |   +------------------+   +-----------------+               |     |
|   |                                                            |     |
|   +------+------+--------------------------+----+--------------+     |
|          |      |                          |    |                    |
|       +--v--+ +-v---+                    +-v-+ +v---+                |
|       | MC  | | MC  | (DDR5 channels)    |PCIe| |Sys |                |
|       +-----+ +-----+                    +---+ +Agnt|                |
|                                                +----+                |
+----------------------------------------------------------------------+
```

Key components:

- **P-cores** &mdash; the wide OoO beasts (Golden/Raptor/Lion Cove).
- **E-cores** &mdash; in-order or modestly OoO, area- and power-efficient
  (Tremont / Gracemont / Crestmont). Grouped into clusters of 4 sharing L2.
- **Last-Level Cache (LLC)** &mdash; an "L3" of tens of MB, sliced by cache
  line address, attached to a *ring bus* (or *mesh* on Xeons).
- **Ring bus** &mdash; bidirectional ring of stops; each P-core, each
  LLC slice, the system agent, the iGPU, and the E-core clusters all sit
  on stops. Two ring-clocks per hop.
- **Memory Controller (MC)** &mdash; DDR4 / DDR5 PHY.
- **System Agent** &mdash; PCIe root complex, DMI link to the chipset,
  display engine, power management unit (PCU / Punit).

---

## Core block diagram

Here is the canonical Golden Cove P-core. Boxes correspond to physical
units; numbers in parentheses are widths or sizes Intel has published.

```
                    +----------------------+
                    |  Branch Predictor    |     (TAGE-like + ITA + RAS)
                    |  + BTB (12k+ entries)|
                    +-----+----------------+
                          | predicted PC
                          v
        +-----------------------------+        +------------------+
        |    L1 Instruction Cache     |        | Instruction TLB  |
        |    32 KB, 8-way, 64B lines  |--------|  (256 entry L1)  |
        +--------+----------+---------+        +------------------+
                 |          |
       64B/cycle |          | 32B/cycle
                 v          v
       +------------+   +-------------------------+
       |  Predecode |   |       Uop Cache (DSB)   |
       |  + Length  |   |  ~4096 uops, 8 entries  |
       |  + xform   |   |  delivers up to 8/clk   |
       +-----+------+   +------------+------------+
             |                       |
             v                       |
       +-----------------------+     |
       |  Decoders (MITE)      |     |
       |  6 lanes:             |     |
       |   1 complex + 5 simple|     |
       |  6 uops/clk peak      |     |
       +-----------+-----------+     |
                   |                 |
                   +--------+--------+
                            v
                   +-----------------+
                   |   uop queue     |    (LSD-capable: replays
                   |  + LSD (loops)  |     loops without re-fetch)
                   +--------+--------+
                            |
                            v  up to 6 uops/clk
              +-------------+--------------+
              |   Allocate / Rename / Retire|
              |   integer & vector RAT      |    (writes ROB + RS)
              |   ROB ~512 entries          |
              +-------------+--------------+
                            |
       +--------------------+--------------------+
       |                                         |
       v                                         v
  +----------+  Unified scheduler              +-----------+
  |  Int RF  |  ~~~~~~~~~~~~~~~~~~~~~~~        | Vector RF |
  | (256+)   |  Reservation Station            | (~330)    |
  +----+-----+  205 entries, splits to ports   +-----+-----+
       |                                              |
       +--+-----+-----+-----+-----+-----+-----+-----+-+-----+
          |     |     |     |     |     |     |     |       |
          v     v     v     v     v     v     v     v       v
        P0    P1    P2    P3    P4    P5    P6    P7      P8/9/10
        ALU   ALU   AGU   AGU   STD   ALU   ALU   AGU    Vector lanes
        BR    JEU   Load  Load  Store Vec   Vec   Load   (FMA, AVX-512)
        FMA              (memory pipeline)               + Load/Store
        DIV
        Vec
                                ...
                            +-----------+
                            |   L1D     |  48 KB, 12-way
                            |   2 loads |  +1 store per cycle
                            +-----+-----+
                                  |
                            +-----+-----+
                            |    L2     |  1.25-2 MB, 16-way, ~12 cyc
                            +-----+-----+
                                  |
                            +-----+-----+
                            |    L3     |  shared LLC slice via ring
                            |  (LLC)    |  3-30+ MB, ~40-60 cyc local
                            +-----------+
                                  |
                            +-----+-----+
                            |   DRAM    |  ~100 ns
                            +-----------+
```

---

## The front end

The front end's only job is **to feed uops to the back end as fast as the
back end can swallow them**. In real workloads it usually can't.

### Branch predictor

The single most important block in a modern core. A Golden Cove-class
predictor combines:

- **L1 BTB** (Branch Target Buffer): ~128-1024 entries, single-cycle lookup.
- **L2 BTB**: ~4000-12000 entries, 1-2 cycle penalty.
- **TAGE-like direction predictor**: a stack of geometrically-sized,
  PC-and-history-indexed tables that bet on the direction of conditional
  branches. State-of-the-art for ~15 years.
- **ITA / Indirect Target Array**: predicts indirect call/jump targets
  (think virtual function dispatch).
- **RAS / Return Address Stack**: shadow stack of call targets; predicts
  return addresses without consulting memory.

Misprediction penalty: ~15-20 cycles on Golden Cove. **Every misprediction
flushes the entire OoO window.** This is why branch-heavy code (interpreters,
parsers) historically struggles on wide OoO machines.

### L1I, ITLB, fetch

- 32 KB, 8-way L1 instruction cache.
- 64 B per cache line; ~16 bytes of x86 = ~4 average-length instructions.
- Fetch bandwidth: up to 32 bytes/cycle from L1I when the uop cache misses.
- ITLB: 256-entry L1 ITLB + larger L2 (shared with DTLB).

### Legacy decoders (MITE) vs uop cache (DSB)

x86 is *variable length*: 1..15 bytes per instruction. Just figuring out
where the next instruction starts is non-trivial.

- **MITE (Micro-Instruction Translation Engine)**: the legacy decoders.
  6 lanes: 1 "complex" (can produce up to 4 uops) + 5 "simple" (1 uop each).
  Max 6 uops/cycle. Lots of length-decoding hardware. Hot, expensive.
- **DSB (uop cache)**: a 4096-uop SRAM that stores already-decoded uops.
  Hits deliver up to 8 uops/clock with zero decoding cost. For typical hot
  loops, DSB hit rate is >70%. **This is why Intel chips don't melt.**
- **MSROM / microcode ROM**: very complex instructions (e.g., string ops,
  segment ops, mode transitions) get expanded by a microsequencer that
  reads a microcode ROM.

The decoder is the part that fundamentally has no equivalent in our
`x86lite32`: we used fixed-width 32-bit encoding, so we needed no length
predecode, no DSB, no MSROM. *That single decision* is the architectural
difference between RISC and CISC at the front end.

### Loop Stream Detector (LSD)

If a small loop fits inside the uop queue (~70 uops), the LSD locks it
there and replays uops *without re-fetching from L1I or DSB*. Saves power
and serialisation hazard in tight loops.

### Allocate / rename / retire

Up to 6 uops per cycle move from the uop queue into the OoO engine. Three
things happen simultaneously:

1. **Register renaming**: each uop's source/dest register names are
   translated from architectural names (RAX, RBX, ZMM0...) to *physical
   register numbers* in a much larger physical register file (~256 INT,
   ~330 vector). This breaks false dependencies (WAR, WAW).
2. **ROB allocation**: each uop gets an ROB entry. The ROB holds in-flight
   uops in program order, even though they execute out of order.
3. **Scheduler insertion**: each uop is placed into the reservation
   station / unified scheduler, where it waits until all its operands are
   ready.

---

## The out-of-order engine

### Reorder Buffer (ROB)

~512 entries in Golden Cove (had been 224, 352, 384 in earlier
generations; Lion Cove goes higher still). The ROB is the bookkeeping
ledger: it remembers, for every in-flight instruction, what register it
will write to and whether it has completed. **Retirement happens in
program order**, even though execution didn't &mdash; this is how
precise exceptions are preserved.

### Schedulers and dispatch ports

The unified scheduler (~205 entries) holds uops waiting for ready
operands. On any given cycle it can dispatch up to ~12 uops across the
execution ports:

- **P0, P1, P5, P6**: ALU / shift / branch / vector lanes (4-wide integer
  ALU front!)
- **P2, P3**: load units (2 loads/cycle)
- **P4**: store data
- **P7**: store address generation
- **Vector pipes**: 256-bit (AVX2) on all parts; **512-bit (AVX-512) on
  server parts + a few desktop SKUs**. Server Xeon parts have 2x 512-bit
  FMA pipes giving 32 single-precision flops per cycle.

### Execution units (highlights)

- **Integer ALU**: 4-wide.
- **Branch JEU**: dedicated branch resolution.
- **Integer multiply / divide**: pipelined multiply, iterative divide.
- **Vector FMA**: fused multiply-add at 256-bit and (where present) 512-bit.
- **Vector permute / shuffle / pack / unpack**: critical for SIMD code.
- **AMX tile units** (Sapphire Rapids+): a *matrix*-multiply accelerator
  that operates on 1 KB "tiles" and can do BF16 / INT8 matrix products at
  hundreds of TOPS per socket.

---

## The memory subsystem

### L1D

48 KB, 12-way, 6-cycle load-to-use, 4 cycles best case for an integer
load. Supports 2 loads and 1 store per cycle. Has its own store buffer
(~72 entries) and load buffer (~136 entries). The store buffer enables
out-of-order stores that retire in order.

### L2

1.25-2 MB per core (P-core), 16-way, ~12-cycle access. Holds both
instructions and data. Inclusive-ish of L1.

### L3 / LLC

Shared, sliced by hash function across ring stops. 3-4 MB per slice.
Local-slice ~40 cycles; far-slice ~60 cycles; ring traversal adds latency
proportional to distance. **On Xeons, L3 is replaced by a 2D mesh** to
scale beyond 12-ish cores.

### Memory controllers + DRAM

DDR4/DDR5; HBM on certain Xeon Max parts. DRAM access is ~100 ns latency,
~50 GB/s per channel, multiple channels per package.

### Hardware prefetchers

Up to 4 independent prefetchers per core:

- **L1 streamer**: detects sequential or strided access to consecutive
  cache lines.
- **L1 IP-based**: per-instruction-pointer pattern recognition.
- **L2 streamer**: similar but at L2 granularity.
- **L2 spatial / next-line / DCU**: various heuristics.

Prefetchers regularly account for >50% of "L1 hits" on memory-bound code.

---

## Vector and matrix extensions

The x86 SIMD lineage:

| ISA           | Year | Width  | What it added                      |
|---------------|------|--------|------------------------------------|
| MMX           | 1996 | 64b    | first packed integer SIMD          |
| SSE           | 1999 | 128b   | single-precision FP, 8 XMM regs    |
| SSE2          | 2001 | 128b   | int + double SIMD                  |
| SSE3, SSSE3   | 2004-6| 128b  | horizontal ops                     |
| SSE4.1, 4.2   | 2007-8| 128b  | string ops, dot product            |
| AVX           | 2011 | 256b   | YMM regs, 3-operand non-destructive|
| AVX2          | 2013 | 256b   | int 256, gather, FMA, BMI          |
| AVX-512       | 2016 | 512b   | ZMM regs, mask regs, scatter, conflict detect |
| AVX-512 VL/BW/DQ | 2017+ | 512b | per-subset extensions             |
| AVX-512 VNNI  | 2019 | 512b   | int8 dot product (neural nets)     |
| AVX-512 BF16  | 2020 | 512b   | bfloat16 multiply-accumulate       |
| AMX           | 2023 | 1KB tiles | matrix multiplications          |
| AVX10         | 2024+| 256/512| consolidation of AVX-512 across P/E|

AVX-512 deserves a note: each 512-bit instruction can do up to 16
single-precision flops; with two FMA pipes per cycle, **a Xeon P-core can
do 32 SP flops per cycle**, or 1.024 TFLOPS at 4 GHz, in a single core.

---

## Hyper-Threading (SMT)

Each P-core can run **two software threads simultaneously** on one
physical core. Most resources are shared (caches, schedulers, ports);
some are partitioned (ROB slots, load/store buffers); some are tagged
per-thread (RAS, branch predictor history). HT roughly buys 10-30% extra
throughput on a workload that has slack (e.g., latency-bound code), at
the cost of side-channel surface area.

Intel removed HT from some recent client desktop P-cores (Lion Cove on
Lunar Lake) to free up area for other features and to reduce
side-channel risk.

---

## P-core vs E-core (Alder Lake on)

Since Alder Lake (12th gen Core, 2021), Intel ships hybrid CPUs:

| Axis              | P-core (Golden/Raptor/Lion Cove) | E-core (Gracemont/Crestmont) |
|-------------------|------------------------------------|------------------------------|
| Pipeline width    | 6-wide rename, 12-port back end   | 5-wide rename, 8-port back end |
| OoO window        | ROB ~512                          | ROB ~256                     |
| L2 per core       | 1.25-2 MB                         | 4 MB **shared per 4 cores**  |
| AVX-512           | yes (server) / variable (client)  | no                           |
| Hyper-Threading   | yes (mostly)                      | no                           |
| Peak freq         | ~5.5-6.0 GHz                      | ~3.5-4.0 GHz                 |
| Area              | huge                              | ~4x smaller                  |
| Use case          | latency-sensitive single thread   | parallel throughput tasks    |

The OS scheduler (with Intel Thread Director's help) places threads on the
right core type. This is the "big.LITTLE" idea that ARM popularised in the
mobile world, finally arrived on x86 desktops.

---

## Security mitigations

Spectre/Meltdown (2017-2018) and successors changed CPU design forever.
Modern Intel cores include:

- **Indirect Branch Restricted Speculation (IBRS)**: prevents speculative
  indirect branches from being trained across privilege boundaries.
- **Single Thread Indirect Branch Predictor (STIBP)**: isolates indirect
  branch predictions per HT thread.
- **Indirect Branch Predictor Barrier (IBPB)**: software-issued flush.
- **L1 Data Cache Flush (L1D_FLUSH)** for VM exits.
- **Speculative Store Bypass Disable (SSBD)**.
- Increased *retirement-window squashing* on certain mis-speculation
  patterns (eIBRS, BHI mitigations).
- **Linear Address Masking (LAM)**, **CET (Control-flow Enforcement
  Technology)** for ROP/JOP attack surface reduction.

Cost: typically 1-15% on workloads that depend on indirect branches or
heavy kernel transitions.

---

## Performance numbers, roughly

| Metric              | Lion Cove (Lunar/Arrow Lake, 2024) |
|---------------------|------------------------------------|
| Decode width        | 8 uops/cycle                       |
| Rename width        | ~8 uops/cycle                      |
| ROB                 | ~576 entries                       |
| Reservation Stations| ~250+                              |
| Load/Store buffers  | ~150 / ~108                        |
| Phys INT regs       | ~390                               |
| Phys vec regs       | ~432                               |
| Integer IPC ceiling | ~5-6 in best cases                 |
| AVX-512 SP flops/cy | up to 32 (server)                  |
| Branch mispred cost | ~15-18 cycles                      |
| L1D latency         | 4-6 cycles                         |
| L2 latency          | ~16 cycles                         |
| LLC latency         | ~40-60 cycles                      |
| DRAM latency        | ~80-110 ns                         |
| Frequency           | 5.0-6.2 GHz turbo                  |

---

## How "your" SCP would have to grow

If you took the `scp16` skeleton and tried to evolve it toward Lion Cove,
each step is a real engineering project:

| Step | What you add                              | Concept introduced |
|------|-------------------------------------------|-----------------------------|
| 1    | Pipeline (IF/ID/EX/MEM/WB)                | Hazard detection, forwarding |
| 2    | Branch predictor (1-bit -> TAGE)          | Speculation                  |
| 3    | I-cache + D-cache                         | Memory hierarchy             |
| 4    | TLB + virtual memory                      | Translation, page tables     |
| 5    | Multiple-issue (superscalar)              | Issue logic, dependency tracking |
| 6    | Register renaming                         | Physical reg file, RAT       |
| 7    | Reorder Buffer + precise exceptions       | Retirement                   |
| 8    | Out-of-order scheduler                    | Wakeup/select, age-based picking |
| 9    | Store buffer + memory disambiguation      | Memory dependence prediction |
| 10   | SIMD lanes (128/256/512-bit)              | Wide data paths              |
| 11   | Microcode for complex insns               | Microsequencer               |
| 12   | Multi-core + cache coherence (MESI/MOESI) | Coherence protocol           |
| 13   | Hyper-Threading                           | Per-thread tagging           |
| 14   | Hardware mitigations                      | Side-channel hardening       |

Each of those is *itself* a textbook chapter and a 6+ month design
project. Read 250 lines of `cores/x86lite32/rtl/` and remember: every
P-core inside the Intel CPU running this README on your monitor is the
result of fourteen consecutive applications of those ideas, executed by
hundreds of engineers across decades.

---

## Further reading

- **Intel 64 and IA-32 Architectures Optimization Reference Manual**
  (Intel Order Number 248966) &mdash; chapter 2 is the canonical Golden
  Cove microarchitecture description.
- **Intel Software Developer's Manual** Vols 1-3 &mdash; ISA, system
  programming.
- **Agner Fog**, *Microarchitecture of Intel, AMD and VIA CPUs* &mdash;
  long-running independent dissection.
- **ChipsAndCheese.com** &mdash; modern, detailed independent writeups of
  each new Intel core.
- **Anandtech's "Golden Cove" deep dive (2021)** &mdash; rich block diagrams.
- Hennessy & Patterson, *Computer Architecture: A Quantitative Approach*
  &mdash; the academic version of everything here.
