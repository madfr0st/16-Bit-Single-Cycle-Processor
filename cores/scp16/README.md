# scp16 &mdash; 16-bit Single-Cycle Processor (the starter core)

This is the original, learning-grade core. **Read this first** if you have
never built a CPU before. It's about 250 lines of Verilog and supports
nine instructions:

```
ADD  SUB  AND  SLL  ADDI  LW  SW  BEQ  BNE  JMP
```

Full description, datapath walkthrough, worked instruction traces, bug-fix
log, and exercises live in the **top-level [`README.md`](../../README.md)**.

Other cores in this repo:

- [`../x86lite32/`](../x86lite32/) &mdash; 32-bit CISC-style core inspired by x86.
- [`../armlite32/`](../armlite32/) &mdash; 32-bit RISC-style core inspired by ARMv4.

---

## Layout

```
scp16/
├── rtl/                  synthesizable Verilog
├── sim/                  testbench + waveform layout + demo program
└── constraints/          Basys 3 (Artix-7) pinout
```

## Quick start

From the **repository root**:

```bash
# Icarus simulation
iverilog -g2012 -o build_sim/scp16_tb.vvp \
    cores/scp16/sim/cpu_tb.v cores/scp16/rtl/*.v
vvp build_sim/scp16_tb.vvp

# Vivado project regen (Tcl console)
source scripts/create_project.tcl   # generates project for all 3 cores
```
