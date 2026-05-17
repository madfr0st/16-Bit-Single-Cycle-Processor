# NVIDIA GPU Deep Dive

> A guided tour of modern NVIDIA GPU microarchitecture, focused on the
> Hopper / Blackwell generation (H100, H200, B100, B200, GB200). This is
> what the `gpulite32` core in this repo is a 0.00001% caricature of.
>
> All facts here come from publicly available material: NVIDIA's
> architecture whitepapers, GTC keynotes, the CUDA C++ Programming Guide,
> PTX ISA Manual, *Programming Massively Parallel Processors* (Kirk &
> Hwu), the NVIDIA Hopper Architecture Whitepaper, and detailed
> third-party deep dives (Anandtech, ChipsAndCheese, RealWorldTech, Tim
> Dettmers, Modal Labs, SemiAnalysis).

---

## Table of contents

1. [What "GPU" actually means](#what-gpu-actually-means)
2. [The SIMT execution model &mdash; how a GPU thinks](#the-simt-execution-model)
3. [Outside view &mdash; a Hopper H100 SXM at a glance](#outside-view--a-hopper-h100-at-a-glance)
4. [Inside one Streaming Multiprocessor (SM)](#inside-one-streaming-multiprocessor-sm)
5. [CUDA cores &mdash; the lanes](#cuda-cores--the-lanes)
6. [Tensor Cores &mdash; the matrix engine](#tensor-cores--the-matrix-engine)
7. [The warp scheduler](#the-warp-scheduler)
8. [Memory hierarchy](#memory-hierarchy)
9. [PTX and SASS &mdash; the two ISAs](#ptx-and-sass--the-two-isas)
10. [CUDA programming model in one page](#cuda-programming-model-in-one-page)
11. [Divergence: branches in a SIMD machine](#divergence-branches-in-a-simd-machine)
12. [Asynchronous everything &mdash; TMA, copy engines, MIG](#asynchronous-everything)
13. [NVLink, NVSwitch, and the multi-GPU story](#nvlink-nvswitch-and-the-multi-gpu-story)
14. [Performance numbers, roughly](#performance-numbers-roughly)
15. [How "your" gpulite32 would have to grow](#how-your-gpulite32-would-have-to-grow)
16. [Further reading](#further-reading)

---

## What "GPU" actually means

A modern NVIDIA datacenter GPU is a **massively parallel throughput
machine**. Where a CPU optimizes the *latency* of one thread (with deep
OoO, big caches, branch prediction), a GPU optimizes the *throughput* of
many thousands of threads sharing the same instruction stream.

- A Hopper H100 has **132 Streaming Multiprocessors (SMs)**, each with
  ~128 CUDA cores and 4 Tensor Cores.
- It schedules **~2048 threads per SM** = ~270,000 threads concurrently
  on chip.
- It can sustain ~**60 TFLOPS FP32, 1979 TFLOPS FP16/BF16 (Tensor
  Cores), 3958 TFLOPS FP8** &mdash; numbers that would have been called
  "supercomputer-class" five years ago.
- It draws **350-700 W** depending on form factor.

This document explains how, structurally, that's possible.

---

## The SIMT execution model

The defining idea of NVIDIA GPUs since Tesla (G80, 2006) is **SIMT
&mdash; Single Instruction, Multiple Threads**.

- Threads are grouped into **warps of 32**.
- One warp executes **the same instruction in lockstep** across its 32
  threads each cycle.
- Each thread inside the warp has its own register state, its own
  predicate, and its own data &mdash; so 32 threads doing "the same
  thing" can do useful *different* work because they operate on
  different inputs.

In gpulite32 the warp shrinks to 8 lanes; everything else is the same.
The SIMT model is conceptually identical to SIMD (one instruction over a
vector), but the **programming model** is per-thread: you write code
that looks scalar, and the hardware groups your threads into warps.

```
SIMT view from hardware:                       SIMD view (e.g., AVX-512):
+------+------+------+------+...+------+      +-----------------------+
|thread|thread|thread|thread|   |thread|      |  one 512-bit register |
|  0   |  1   |  2   |  3   |   |  31  |      |  16 x 32-bit lanes    |
+------+------+------+------+...+------+      +-----------------------+
  same instruction this cycle                   same instruction
  different register files                      one register file, lanes
```

The key thing is that SIMT lets you write the inner loop as if it were
scalar &mdash; no `_mm512_*` intrinsics, no manual lane indexing &mdash;
and the compiler/scheduler handles the warping. This is why GPGPU
programming exploded in the late 2000s.

---

## Outside view &mdash; a Hopper H100 at a glance

The H100 SXM5 die (TSMC 4N, 80 billion transistors, 814 mm²):

```
+----------------------------------------------------------------------+
|                                                                      |
|   +-----------------------------------------------------------+      |
|   |             GPC 0          GPC 1   ...     GPC 7          |      |
|   |  +----+----+----+----+ +----+----+----+----+ ...          |      |
|   |  | SM | SM | SM | SM | | SM | SM | SM | SM |              |      |
|   |  +----+----+----+----+ +----+----+----+----+              |      |
|   |  | SM | SM | SM | SM | | SM | SM | SM | SM |              |      |
|   |  +----+----+----+----+ +----+----+----+----+              |      |
|   |  ... up to 18 SMs per GPC                                 |      |
|   |  (132 SMs total enabled on H100)                          |      |
|   +-----------------------------------------------------------+      |
|                              |                                       |
|                              v                                       |
|   +-----------------------------------------------------------+      |
|   |               L2 CACHE  (~50 MB, banked)                  |      |
|   +-----------------------------------------------------------+      |
|                              |                                       |
|     +-------+ +-------+ ... +-------+ +-------+                      |
|     | HBM3  | | HBM3  |     | HBM3  | | HBM3  |  (5 stacks, 80 GB)   |
|     +-------+ +-------+ ... +-------+ +-------+                      |
|                                                                      |
|     +---------------+   +---------+   +-----------+                  |
|     |  NVLink 4 x18 |   | PCIe 5  |   | Copy engs |                  |
|     +---------------+   +---------+   +-----------+                  |
+----------------------------------------------------------------------+
```

Key blocks:

- **GPCs (Graphics Processing Clusters)**: 8 of them on H100, each
  containing up to 18 SMs. Mostly a topological grouping for ray-tracing
  and rasterizer balancing on consumer parts; on H100 the RT/RAS is
  absent (compute-only chip).
- **SMs (Streaming Multiprocessors)**: 132 enabled on H100. The execution
  workhorses. One gets dissected below.
- **L2 cache**: ~50 MB on H100, split into two halves with crossbar
  connectivity. Acts as the global mailbox for SMs.
- **HBM3**: 5 stacks of 16 GB = 80 GB, 3.35 TB/s aggregate bandwidth.
  HBM3e on H200 bumps this to 4.8 TB/s.
- **NVLink 4**: 18 links of 50 GB/s each = 900 GB/s aggregate to other
  GPUs (via NVSwitch).
- **PCIe 5.0 x16**: 128 GB/s to the host CPU.
- **Copy engines**: dedicated DMA engines for async memcpy between
  host, device, and peer GPUs.
- **TMA (Tensor Memory Accelerator)**, new in Hopper: a programmable
  async copy engine for tile-shaped data movement, freeing CUDA cores
  from address-generation work for big matmuls.

---

## Inside one Streaming Multiprocessor (SM)

A Hopper SM is the most important block in the chip. Each one looks
roughly like:

```
+---------------------------------------------------------------------+
| SM                                                                  |
|                                                                     |
|   +-------------------------------------------------------------+   |
|   |                L1 Instruction Cache                         |   |
|   +-----+-------------+-------------+-------------+-------------+   |
|         |             |             |             |                 |
|         v             v             v             v                 |
|   +----------+  +----------+  +----------+  +----------+            |
|   | Warp Sch | | Warp Sch | | Warp Sch | | Warp Sch |    (4 of)    |
|   | + DPU    | | + DPU    | | + DPU    | | + DPU    |              |
|   +-----+----+ +-----+----+ +-----+----+ +-----+----+              |
|         |            |            |            |                    |
|         |            |            |            |                    |
|   each sub-partition has:                                           |
|       - 16K x 32b register file slice (= 64 KB)                    |
|       - 16 FP32 / INT32 CUDA cores                                  |
|       - 8 FP64 cores                                                |
|       - 1 Tensor Core                                               |
|       - 1 Load/Store unit cluster                                   |
|       - 1 Special Function Unit (SFU)                               |
|                                                                     |
|         four sub-partitions per SM ----------------------+          |
|                                                          |          |
|   +-------------------------------------------------+   v          |
|   |          Shared Memory / L1 Data Cache          | (228 KB on   |
|   |          dynamically partitionable               |  Hopper, up |
|   +-------------------------------------------------+  to 100 KB  |
|                                                          shared)   |
|                                                                     |
|   +-------------------------------------------------+               |
|   |  TMA  (Tensor Memory Accelerator, Hopper+)      |               |
|   +-------------------------------------------------+               |
+---------------------------------------------------------------------+
```

Per Hopper SM (from the H100 whitepaper):

| Resource                              | Per SM                              |
|---------------------------------------|--------------------------------------|
| FP32 / INT32 CUDA cores               | 128 (32 per sub-partition × 4)       |
| FP64 cores                            | 64                                   |
| Tensor Cores (4th gen)                | 4 (one per sub-partition)            |
| Register file                         | 256 KB (64 KB × 4)                   |
| Shared memory + L1                    | 228 KB total, dynamically split      |
| Max threads in flight                 | 2048 (64 warps × 32 threads)         |
| Max thread blocks resident            | 32                                   |
| Warp schedulers                       | 4                                    |
| Issue rate                            | 4 warp instructions / clock          |

---

## CUDA cores &mdash; the lanes

A "CUDA core" is, mechanically, **one 32-bit ALU lane**. It's NOT a
"core" in the CPU sense (it has no fetcher, no decoder, no instruction
pointer of its own). It's just a piece of execution hardware that a
warp dispatch can light up for one cycle.

A Hopper FP32/INT32 CUDA core can do:

- 1× FMA32 per clock
- 1× simple integer ALU op per clock

Per SM you have 128 of them, so 128 FMAs/clock = 256 single-precision
flops/clock. At ~1.8 GHz, that's ~460 GFLOPS FP32 *per SM*. Multiply by
132 SMs = ~60 TFLOPS, matching NVIDIA's advertised number.

The trick is that to *feed* 128 CUDA cores per cycle, the SM has to
issue **at least 4 warp instructions per cycle** (4 × 32 lanes = 128).
That's why there are 4 warp schedulers per SM.

In gpulite32 there are 8 lanes and 1 warp scheduler. To scale up:

1. Widen the warp from 8 to 32.
2. Add 4× more lanes (32 per scheduler).
3. Add 3 more warp schedulers, with 3 more independent warp PCs.
4. Round-robin (or score-board) the warp scheduler over many in-flight
   warps to hide memory latency.

That last step is the big "latency-hiding-by-massive-multithreading"
idea that defines GPU performance.

---

## Tensor Cores &mdash; the matrix engine

Introduced in Volta (V100, 2017) and a generational arms-race ever
since, Tensor Cores are **dedicated matrix multiply-accumulate units**.
A single 4th-gen Tensor Core (Hopper) executes:

```
D = A × B + C
where A, B are small matrices and C, D are accumulators
```

…in **a single instruction**. The supported tile sizes vary by data
type. Example for FP16 multiplied accumulating into FP32 on Hopper:

```
A : 16 × 8   FP16
B :  8 × 8   FP16
C : 16 × 8   FP32
D : 16 × 8   FP32
```

That's 16×8×8 = 1024 multiply-adds = 2048 flops in a single Tensor Core
instruction. Four Tensor Cores per SM × 132 SMs × ~1.8 GHz ≈ **1979
TFLOPS FP16 with FP32 accumulate**.

Hopper's Tensor Cores also added:

- **FP8 (E4M3 + E5M2)**: 2× throughput vs FP16 = ~3958 TFLOPS FP8.
- **Transformer Engine**: per-layer FP8 calibration to keep accuracy
  while using fp8 hardware.
- **DPX instructions**: hardware acceleration for dynamic programming.

On Blackwell (2024), the Tensor Cores got 2× wider again, plus native
FP4 / FP6 support.

The dirty secret is that **virtually all of modern ML's compute happens
in Tensor Cores**, not CUDA cores. Once you write `cublasGemmEx` or any
PyTorch matmul, you're using TC.

---

## The warp scheduler

Each SM sub-partition has its own warp scheduler. Per cycle it:

1. Looks at the up-to-16 warps assigned to this sub-partition.
2. Filters out warps that are *not ready* (waiting on memory, barrier,
   stall).
3. Picks one ready warp (round-robin / "Greedy-than-Oldest" / similar
   policy).
4. Issues one instruction from that warp to the lanes / Tensor Core / LSU.

That instruction takes one *issue* cycle, but the *latency* of the
instruction could be many cycles (memory load = 100s of cycles, FMA = a
few cycles). The scheduler **doesn't wait**: next cycle it picks a
different ready warp and issues from it. As long as enough warps are
in flight, the lanes are never idle. **This is how GPUs hide latency:
not with OoO speculation like CPUs, but with massive concurrency.**

Quantitatively: if your DRAM round-trip is 600 cycles and one warp blocks
for one round-trip after every issue, you need 600 in-flight warps to
keep one lane busy. A Hopper SM holds 64 warps × 4 sub-partitions = 256
warps; not 600, but the LSU also queues many requests per warp, and
real workloads have less than 100% miss rates. The "occupancy"
metric in CUDA profiling literally measures how close you get to the
2048-thread per SM ceiling.

---

## Memory hierarchy

The single most important fact about GPU programming is **the memory
hierarchy is steeper and faster than you think**.

| Level                 | Size on H100   | Latency (cycles) | Bandwidth (TB/s) |
|-----------------------|-----------------|-------------------|-------------------|
| Registers (per-thread)| 256 KB / SM    | 0 (within FMA)    | ~120 (per SM)     |
| Shared mem / L1       | 228 KB / SM    | ~20-30            | ~30 (per SM)      |
| L2 cache              | 50 MB chip     | ~250-300          | ~12 (chip total)  |
| HBM3                  | 80 GB chip     | ~600              | 3.35 (chip)       |
| NVLink to peer GPU    | -              | ~1000+            | 0.9 (chip total)  |
| PCIe to host          | -              | ~3000+            | 0.128             |

A few non-obvious consequences:

- **Memory coalescing**: if all 32 threads in a warp touch addresses
  inside the same 128-byte sector, the warp's load is *one* memory
  transaction. If they touch 32 different sectors, it's 32. **An order
  of magnitude** in throughput hangs on which pattern your kernel
  generates.
- **Shared memory bank conflicts**: shared memory is split into 32
  banks. Two threads in a warp touching the same bank in the same cycle
  serialize. A 32-way bank-conflicted load is 32× slower than a
  conflict-free one.
- **Registers don't spill nicely**: each thread is limited to a fixed
  number of registers (255 on Hopper). Exceeding that "spills" them to
  *thread-local memory*, which is actually a slice of L2/HBM. Register
  pressure is the single biggest knob in CUDA performance tuning.

---

## PTX and SASS &mdash; the two ISAs

NVIDIA exposes two ISAs to programmers:

### PTX (Parallel Thread Execution)

A *virtual* ISA, like a portable IR. The CUDA compiler (`nvcc`) emits
PTX. The driver JIT-compiles PTX to SASS at runtime, so a PTX binary
runs on any GPU generation. PTX is documented in NVIDIA's *PTX ISA
Reference*.

Example PTX (one warp computes c = a + b):

```ptx
.entry vecadd_kernel (
    .param .u64 a_ptr,
    .param .u64 b_ptr,
    .param .u64 c_ptr
)
{
    .reg .u32 %r<5>;
    .reg .u64 %rd<8>;
    .reg .f32 %f<4>;

    ld.param.u64    %rd1, [a_ptr];
    ld.param.u64    %rd2, [b_ptr];
    ld.param.u64    %rd3, [c_ptr];
    cvta.to.global.u64 %rd4, %rd1;
    cvta.to.global.u64 %rd5, %rd2;
    cvta.to.global.u64 %rd6, %rd3;

    mov.u32         %r1, %ntid.x;
    mov.u32         %r2, %ctaid.x;
    mov.u32         %r3, %tid.x;
    mad.lo.s32      %r4, %r1, %r2, %r3;   // i = blockDim.x * blockIdx.x + threadIdx.x

    mul.wide.s32    %rd7, %r4, 4;
    add.s64         %rd5, %rd5, %rd7;
    add.s64         %rd4, %rd4, %rd7;
    add.s64         %rd6, %rd6, %rd7;

    ld.global.f32   %f1, [%rd4];
    ld.global.f32   %f2, [%rd5];
    add.f32         %f3, %f1, %f2;
    st.global.f32   [%rd6], %f3;

    ret;
}
```

Notice the syntax echoes gpulite32: `ld.global`, `st.global`, `%tid.x`,
`%ntid.x`, three-operand instructions, predicated execution (not shown).
The biggest difference is that PTX has **infinite virtual registers**
which the compiler allocates physically per generation.

### SASS (Streaming Assembler)

The **native** ISA of an actual NVIDIA GPU generation. Hopper SASS,
Ampere SASS, Turing SASS &mdash; all different. NOT officially
documented, but reverse-engineered by `nvdisasm`, Maxas, NervanaSys.
This is the instruction stream the warp scheduler actually issues.

Real SASS for the above kernel looks like:

```
HFMA2.MMA R4, RZ, RZ, 0, 1
S2R R0, SR_CTAID.X
S2R R5, SR_TID.X
IMAD R0, R0, c[0x0][0x0], R5     // i = ctaid * ntid + tid
IADD3 R2, P0, R0.reuse, c[0x0][0x178], RZ
IADD3.X R3, R0.HI, c[0x0][0x17c], RZ, P0, !PT
LDG.E.SYS R2, [R2]
LDG.E.SYS R3, [R3]
FADD R4, R2, R3
STG.E.SYS [R6], R4
EXIT
```

For ML-class kernels you'd see `HMMA` (Hopper Matrix Multiply-
Accumulate) instructions doing tile multiplications on Tensor Cores.

---

## CUDA programming model in one page

```c++
__global__ void vecadd(float* a, float* b, float* c, int n) {
    int i = blockDim.x * blockIdx.x + threadIdx.x;
    if (i < n) c[i] = a[i] + b[i];
}

int main() {
    float *a, *b, *c;
    cudaMallocManaged(&a, N * sizeof(float));
    cudaMallocManaged(&b, N * sizeof(float));
    cudaMallocManaged(&c, N * sizeof(float));

    int threads_per_block = 256;
    int blocks_per_grid = (N + threads_per_block - 1) / threads_per_block;

    vecadd<<<blocks_per_grid, threads_per_block>>>(a, b, c, N);
    cudaDeviceSynchronize();
}
```

The hierarchy:

- **Thread**: one execution context, one set of registers. Like one
  lane.
- **Warp**: 32 threads that execute one instruction in lockstep.
  Hardware concept, not a programmer-visible concept (mostly).
- **Block (CTA, Cooperative Thread Array)**: 1..1024 threads, scheduled
  together on ONE SM. Shares the SM's shared memory. Can synchronise
  with `__syncthreads()`.
- **Grid**: the entire launch, made of many blocks. Blocks are scheduled
  to SMs as SMs free up.

CUDA hides the warp from you most of the time. The `if (i < n)` line in
the kernel is the *only* place warp behaviour shows: lanes for which
`i < n` is false get predicated off &mdash; their hardware time is
wasted, but their state stays consistent.

---

## Divergence: branches in a SIMD machine

What happens when threads in a warp want to take different branches?

```c++
if (threadIdx.x < 16) {
    do_one_thing();
} else {
    do_another_thing();
}
```

In a strict SIMD machine this is impossible &mdash; all lanes execute
the same instruction. NVIDIA's solution since Volta is **Independent
Thread Scheduling (ITS)**: the hardware maintains a per-thread program
counter and uses a *convergence stack* to track which lanes are active
in each branch path. The scheduler issues each path serially, predicating
off the inactive lanes.

Cost: divergent code runs at *path length × 1/divergence-ratio* speed.
A maximally divergent warp (32 different paths) runs ~32× slower than
convergent code.

gpulite32 has a simplified version: branches are taken if *any* lane's
predicate is true, with the inactive lanes silently skipping the
branch-affected work. This is enough for many simple kernels but
doesn't handle the general case.

---

## Asynchronous everything

A defining theme of recent GPU generations is **moving copy / sync /
matmul into dedicated async engines** so CUDA cores can keep computing.

- **TMA (Tensor Memory Accelerator)**: Hopper-introduced async DMA for
  tile-shaped data movement. A single `cp.async.bulk.tensor` instruction
  kicks off a multi-dimensional copy in the background and the warp
  doesn't stall.
- **`cp.async`**: SM-level async copy from global to shared memory (Ampere+).
- **Distributed Shared Memory (DSMEM)**: Hopper SMs can directly access
  other SMs' shared memory via the new SM-to-SM network.
- **Multi-Instance GPU (MIG)**: divides one physical GPU into up to 7
  fully-isolated "virtual GPUs", each with its own SMs, memory partition,
  and L2 slice. Used for multi-tenant inference serving.

---

## NVLink, NVSwitch, and the multi-GPU story

A modern GPU is rarely alone. Training a large LLM uses thousands of
H100s connected by NVLink.

- **NVLink 4** (Hopper): 18 lanes × 50 GB/s = 900 GB/s aggregate per GPU.
- **NVSwitch** (3rd gen): 64-port crossbar; an 8-GPU H100 HGX has 4
  NVSwitches that turn the 8 GPUs into a fully-meshed clique.
- **NVLink network** beyond 8 GPUs: NVSwitch-2 switches in a fabric let
  256+ GPUs see each other's HBM at NVLink speeds (Blackwell GB200
  NVL72 rack: 72 GPUs in one NVLink-coherent domain).

NCCL (NVIDIA Collective Communications Library) implements `all-reduce`,
`all-gather`, etc. on top of NVLink + InfiniBand. It is the secret sauce
under PyTorch DDP and FSDP.

---

## Performance numbers, roughly

| Metric                            | H100 SXM5             | B200 SXM (Blackwell) |
|-----------------------------------|------------------------|------------------------|
| Process node                      | TSMC 4N (custom 5 nm) | TSMC 4NP              |
| Transistors                       | 80 billion             | 208 billion (2 dies)  |
| SMs                               | 132                    | 160 (per die × 2)     |
| FP32 CUDA cores                   | 16,896                 | ~20,480               |
| Tensor Cores                      | 528                    | 640                   |
| Boost clock                       | ~1.83 GHz              | ~1.95 GHz             |
| FP32 (CUDA cores)                 | ~67 TFLOPS             | ~80 TFLOPS            |
| FP16/BF16 (Tensor Cores)          | 1,979 TFLOPS           | 4,500 TFLOPS          |
| FP8 (Tensor Cores)                | 3,958 TFLOPS           | 9,000 TFLOPS          |
| FP4 (Tensor Cores) [Blackwell]    | n/a                    | 18,000 TFLOPS         |
| Memory                            | 80 GB HBM3             | 192 GB HBM3e          |
| Memory bandwidth                  | 3.35 TB/s              | 8 TB/s                |
| NVLink bandwidth                  | 900 GB/s               | 1.8 TB/s              |
| TDP                               | 700 W                  | 1000 W                |

For comparison, a top desktop CPU (Intel i9 / AMD Ryzen 9, ~24 cores)
does ~1 TFLOPS FP32 sustained on AVX-512. A single H100 does ~67 TFLOPS
FP32 from CUDA cores alone, ~2000 TFLOPS FP16 from Tensor Cores. **The
GPU is ~2000× the matrix throughput of the CPU.**

---

## How "your" gpulite32 would have to grow

To evolve gpulite32 into a Hopper SM:

| Step | What you add                                          | Concept                |
|------|--------------------------------------------------------|------------------------|
| 1    | Warp size 32 (instead of 8)                            | Wider SIMD             |
| 2    | 4 warp schedulers per SM                               | Concurrent warps       |
| 3    | Many in-flight warps per scheduler (~16)               | Latency hiding by occupancy |
| 4    | Per-thread register limit (255 regs)                   | Massive register file (256 KB / SM) |
| 5    | FP32 + FP64 + FP16 + BF16 + FP8 + integer + bit lanes  | Multi-precision ALUs   |
| 6    | Tensor Cores (4 per SM)                                | Matrix engine ISA      |
| 7    | Real convergence stack for divergent branches          | ITS in Volta+          |
| 8    | Banked shared memory (32 banks)                        | Bank-conflict avoidance |
| 9    | L1 / L2 caches                                         | Memory hierarchy       |
| 10   | TMA for async tile copy                                | Off-load address gen   |
| 11   | DSMEM (SM-to-SM shared mem)                            | Distributed shared mem |
| 12   | NVLink / NVSwitch fabric                                | Multi-GPU              |
| 13   | MIG (multi-instance GPU)                                | Hardware partitioning  |

That whole list is a 10-year roadmap that NVIDIA has been executing
since Tesla in 2006. The shape of the SM hasn't fundamentally
changed; the *numbers* and the *accelerators bolted on* have grown
exponentially.

---

## Further reading

- **NVIDIA Hopper Architecture Whitepaper** (NVIDIA, 2022) &mdash;
  primary source for H100 microarchitecture.
- **NVIDIA Blackwell Architecture Whitepaper** (NVIDIA, 2024).
- **PTX ISA Reference Manual** (NVIDIA, current).
- **CUDA C++ Programming Guide** (NVIDIA, current).
- **Kirk & Hwu**, *Programming Massively Parallel Processors*, 4th ed.
  &mdash; the textbook for GPU computing.
- **Sengupta, "GPU Architecture and Programming Model"**, ASPLOS
  tutorials.
- **ChipsAndCheese.com** &mdash; "Inside Hopper's SM" series.
- **Tim Dettmers's blog** &mdash; "Which GPU(s) to Get for Deep Learning"
  is a great practical complement to this architectural view.
- **SemiAnalysis newsletter** (Dylan Patel) &mdash; the financial/strategic
  view of GPUs, NVLink, and the AI infrastructure stack.
