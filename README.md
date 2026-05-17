# Four Processors From Scratch &mdash; SCP16, x86lite32, armlite32, gpulite32

> A self-contained learning track that takes you from "what is a clock edge?"
> all the way to "why does an NVIDIA H100 have 16,896 CUDA cores?" &mdash;
> through four working, single-cycle Verilog cores you can read in an
> afternoon and run in a simulator (or on an FPGA) in an evening.

[![HDL](https://img.shields.io/badge/HDL-Verilog--2001-blue)]()
[![Sim](https://img.shields.io/badge/Sim-Vivado%20XSim%20%2F%20Icarus-green)]()
[![FPGA](https://img.shields.io/badge/FPGA-Basys%203%20(Artix--7)-orange)]()
[![Cores](https://img.shields.io/badge/cores-4-purple)]()

---

## The four cores

| Core                                    | Width  | ISA flavour              | What it teaches                                                                                       |
|-----------------------------------------|--------|--------------------------|--------------------------------------------------------------------------------------------------------|
| [`cores/scp16/`](cores/scp16/)          | 16-bit | Custom (MIPS-lite)       | The *bones* of a CPU: PC, IM, control unit, regfile, ALU, DM, MUX. ~250 lines of Verilog.              |
| [`cores/x86lite32/`](cores/x86lite32/)  | 32-bit | x86-flavoured (CISC)     | Condition flags, two-operand format, **PUSH/POP/CALL/RET**, conditional jumps that read flags.         |
| [`cores/armlite32/`](cores/armlite32/)  | 32-bit | ARM-flavoured (RISC)     | **Every** instruction conditional, three-operand format, free **barrel shifter** in ALU operand 2, load/store-only. |
| [`cores/gpulite32/`](cores/gpulite32/)  | 32-bit | NVIDIA-flavoured (SIMT)  | **SIMT execution**: one instruction broadcast to 8 lanes, per-lane registers + predicates, global / shared memory, PTX-style ISA. |

All four are **single-cycle** (one instruction per clock edge for the CPUs;
one warp instruction per cycle for the GPU). That's the right starting
point for understanding processor internals; once you grok it, the
`docs/` folder explains what changes when you scale to a pipelined,
super-scalar, out-of-order beast like a modern Intel core or an Apple M1,
or to a 132-SM, 16,896-CUDA-core throughput monster like an NVIDIA H100.

### Honest scope note

None of `x86lite32`, `armlite32`, or `gpulite32` is the real production
ISA whose name it echoes. Real x86 is 50 years of CISC variable-length
madness with hundreds of instructions, microcode, and a closed
proprietary microarchitecture. Real ARM is a licensed, trademarked ISA
owned by Arm Ltd. Real NVIDIA SASS is undocumented and changes every
generation. What these cores **do** is implement teaching ISAs that
follow the *design philosophy* of each &mdash; so when you later read an
Intel optimisation manual, an ARM ARM, or an NVIDIA whitepaper, the
machinery is familiar.

The "as designed by the gods" treatment of the real chips lives in the
deep-dive docs:

- [`docs/INTEL_DEEP_DIVE.md`](docs/INTEL_DEEP_DIVE.md) &mdash; modern Intel
  P-core: front end, OoO back end, AVX-512, ring bus, P+E core split,
  mitigations.
- [`docs/APPLE_M1_DEEP_DIVE.md`](docs/APPLE_M1_DEEP_DIVE.md) &mdash; M1
  Firestorm / Icestorm, 8-wide decode, ROB ≈ 630, Unified Memory, AMX,
  Fabric, P+E asymmetry.
- [`docs/NVIDIA_DEEP_DIVE.md`](docs/NVIDIA_DEEP_DIVE.md) &mdash; Hopper /
  Blackwell SM: 128 CUDA cores per SM, Tensor Cores, warp schedulers,
  memory hierarchy, PTX/SASS, NVLink, MIG.
- [`docs/COMPARISON.md`](docs/COMPARISON.md) &mdash; numbers side-by-side.

---

## Quick start &mdash; simulate any core

```bash
# install once
sudo apt install iverilog gtkwave        # Linux
brew install icarus-verilog gtkwave      # macOS
# Windows: https://bleyer.org/icarus/

# run a core (pick one)
make -f scripts/sim.mk CORE=scp16
make -f scripts/sim.mk CORE=x86lite32
make -f scripts/sim.mk CORE=armlite32
make -f scripts/sim.mk CORE=gpulite32

make -f scripts/sim.mk CORE=scp16 wave   # open the VCD in GTKWave
```

### Or simulate / synthesise with Vivado

```tcl
# In the Vivado Tcl Console:
cd <path-to-this-repo>
source scripts/create_project.tcl       # creates ./build/ for all 3 cores
```

The `scp16` core has Basys 3 board constraints; the 32-bit cores are
simulation-only out of the box, but the RTL is portable &mdash; you can
add a `top` and `xdc` to put either on an FPGA.

---

## Repository layout

```
.
├── cores/
│   ├── scp16/                  16-bit single-cycle (the starter)
│   │   ├── rtl/
│   │   ├── sim/
│   │   ├── constraints/        Basys 3 xdc
│   │   └── README.md
│   ├── x86lite32/              32-bit CISC-style CPU (x86-flavoured)
│   │   ├── rtl/
│   │   ├── sim/
│   │   └── README.md
│   ├── armlite32/              32-bit RISC-style CPU (ARM-flavoured)
│   │   ├── rtl/
│   │   ├── sim/
│   │   └── README.md
│   └── gpulite32/              32-bit SIMT GPU (NVIDIA-flavoured)
│       ├── rtl/                1 SM + 8 lanes + global/shared mem
│       ├── sim/
│       └── README.md
│
├── docs/                       deep-dive learning material
│   ├── ISA.md                  full ISA reference for all cores
│   ├── DATAPATH.md             datapath diagrams + control flow tables
│   ├── COMPARISON.md           side-by-side: all cores + Intel + M1 + NVIDIA
│   ├── INTEL_DEEP_DIVE.md      modern Intel P-core microarchitecture
│   ├── APPLE_M1_DEEP_DIVE.md   Apple M1 Firestorm + Icestorm microarchitecture
│   └── NVIDIA_DEEP_DIVE.md     NVIDIA Hopper/Blackwell SM, Tensor Cores, PTX
│
├── scripts/
│   ├── create_project.tcl      Vivado project regenerator
│   └── sim.mk                  Icarus Verilog Makefile (CORE=... selector)
│
├── .gitignore                  keeps Vivado build trash out of git
└── README.md                   ← you are here
```

---

## The learning track

Read in this order:

1. **[`cores/scp16/README.md`](cores/scp16/README.md)** &mdash; build the
   minimum-viable CPU. Understand fetch/decode/execute/memory/writeback as
   a single combinational cone collapsing into one clock edge.
2. **[`docs/DATAPATH.md`](docs/DATAPATH.md)** &mdash; the ASCII datapath
   for scp16, every wire labelled. Re-read alongside `rtl/cpu.v`.
3. **[`docs/ISA.md`](docs/ISA.md)** &mdash; the encoding spec for all
   three cores, side by side.
4. **[`cores/x86lite32/README.md`](cores/x86lite32/README.md)** &mdash;
   see how the same single-cycle skeleton stretches to handle CISC features:
   condition flags, two-operand instructions, stack discipline, CALL/RET.
5. **[`cores/armlite32/README.md`](cores/armlite32/README.md)** &mdash; see
   how RISC discipline + barrel-shifted Operand2 + conditional execution
   give you ARM's signature compact code density.
6. **[`cores/gpulite32/README.md`](cores/gpulite32/README.md)** &mdash; see
   what changes when you swap "one instruction, one thread" for "one
   instruction, eight threads in lockstep with their own registers".
7. **[`docs/COMPARISON.md`](docs/COMPARISON.md)** &mdash; what scales
   between a 250-line teaching CPU and a 80 billion-transistor production
   chip.
8. **[`docs/INTEL_DEEP_DIVE.md`](docs/INTEL_DEEP_DIVE.md)** &mdash; how
   Intel does it.
9. **[`docs/APPLE_M1_DEEP_DIVE.md`](docs/APPLE_M1_DEEP_DIVE.md)** &mdash;
   how Apple does it.
10. **[`docs/NVIDIA_DEEP_DIVE.md`](docs/NVIDIA_DEEP_DIVE.md)** &mdash;
    how NVIDIA does it.

---

## Architecture at a glance &mdash; the universal single-cycle skeleton

All three cores share the same five-stage logical structure, collapsed into
one clock period:

```
+----+    +----+    +-----+    +----+    +----+    +----+
| PC |--->| IM |--->| CU  |    | RF |--->|ALU |--->| DM |--->|MUX|---> Rd
+----+    +----+    +-----+    +----+    +----+    +----+    +----+
  ^         |         |                    |         |         ^
  |         |         v                    |         |         |
  |         |     control signals (reg_we, mem_re, mem_we,    |
  |         |         alu_op, immi/imm, jmp/branch ...)        |
  |         +-->branch / jump target back to PC<--------------+
```

The differences across the three cores are:

| Block            | scp16            | x86lite32                  | armlite32                                  |
|------------------|------------------|----------------------------|-------------------------------------------|
| Register file    | 16 x 16          | 16 x 32, R15=ESP side port | 16 x 32, R15=PC mirror                    |
| ALU              | 4 ops            | 11 ops + flag generator    | 16 ops + flag generator                   |
| Operand 2        | direct register  | direct register or imm     | **barrel-shifted register or rot-imm**    |
| Control flow     | BEQ/BNE + JMP    | JE/JNE/JG/JL/JGE/JLE + CALL/RET | every instr can be conditional + B/BL |
| Memory ops       | LW / SW          | LD / ST + PUSH/POP/CALL/RET| LDR / STR                                 |
| Flags            | none             | CF / ZF / SF / OF          | N / Z / C / V                             |
| Decode signals   | 8                | 17                         | 11 + cond predicate                       |

That last row is the single best metric for "ISA complexity": the more
features the front-end has to express, the more control signals fan out of
the decoder.

---

## Why four cores instead of one?

Because the *shape* of an ISA changes the *shape* of the microarchitecture
that runs it &mdash; and the shape of an *execution model* (scalar vs
SIMT) changes everything else.

- **CISC (x86)** was designed for hand-written assembly and tiny memory
  budgets. Two-operand "src/dst combined" instructions, flag-based
  conditional jumps, and complex addressing modes save program bytes.
- **RISC (ARM, MIPS, RISC-V)** was designed for compilers and pipelining.
  Fixed widths, three operands, load/store discipline, and orthogonal
  registers make pipelines easier to build and out-of-order easier to
  schedule.
- **SIMT (NVIDIA CUDA)** was designed for graphics, then repurposed for
  scientific computing and ML. One instruction stream broadcast to many
  lanes, each with its own state. Optimises *throughput*, not latency.
  Hides memory latency through massive concurrency instead of OoO
  speculation.
- **Modern Intel and Apple cores** decode CISC/RISC internally to micro-ops
  (µops) and execute them out-of-order. The "RISC vs CISC" war is
  conceptually over; the war that replaced it is "front-end decode bandwidth
  vs back-end resources".
- **Modern NVIDIA GPUs** don't fight that war at all &mdash; they sidestep
  OoO entirely and use *massive multithreading* (~270k threads on H100)
  to hide latency. Totally different design point.

You can feel that tradeoff in this repo by comparing
`cores/x86lite32/rtl/control_unit.v` (CISC decode) to
`cores/armlite32/rtl/control_unit.v` (RISC decode) to
`cores/gpulite32/rtl/gpu.v` (1 decoder, 8 lanes).

---

## Status & known limitations

- **Synthesis:** `scp16` is FPGA-proven on the Basys 3. The 32-bit cores
  (CPU + GPU) are written to be portable RTL but have not been
  silicon-validated yet at the time of this commit; they should
  synthesise cleanly to any modern FPGA with minimal change.
- **Simulation:** all four cores include a self-contained Icarus
  testbench. Note that `gpulite32` uses unpacked-array port lists
  (SystemVerilog), so compile with `iverilog -g2012`. Code was authored
  carefully; please open an issue if you spot a regression.
- **Verification:** no formal verification or coverage; this is a
  teaching project, not silicon-ready IP.
- **Scope:** see honest scope notes inside each non-scp16 core's README.

---

## Credits & license

This started as the *CA 490 Team 47* 16-bit single-cycle processor lab and
has been heavily revamped + extended with two new 32-bit cores and a deep
documentation set.

Code: MIT. Documentation: CC-BY-4.0. Free to use, modify, and teach with.
