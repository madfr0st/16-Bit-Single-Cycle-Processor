# 16-Bit Single Cycle Processor

Implemented a non-pipelined 16-bit processor with R/I/J-type instructions:  
`ADD, SUB, AND, SLL, ADDI, LW, SW, BEQ, BNE, JMP`

---

## Introduction

### Overview of Project
This project presents the design of a **16-bit processor** capable of performing basic arithmetic, logical, and memory operations.  
It is **non-pipelined** and **single-cycle**, meaning each instruction is completed in a single clock cycle.  

The main objective was to create a simple processor architecture that adheres to a **16-bit instruction set**.

---

## Tools Used
- **Vivado**  
  Used for simulation, testing, and synthesizing Verilog code. It also enabled FPGA hardware implementation and visualization.  
- **Verilog (HDL)**  
  Used to describe hardware modules such as the **ALU**, **Register File**, and **Control Unit**.

---

## Processor Features
- **Single-Cycle Design** – Each instruction completes in one clock cycle.  
- **Non-Pipelined** – Instructions execute sequentially without overlap.  
- **16-bit Word Size** – Handles 16-bit data at a time.  
- **Basic Instruction Set** – Supports arithmetic, logical, memory, and control flow instructions:  
  `ADD, SUB, SLL, AND, LW, SW, BEQ, BNE, JMP`

---

## Architecture

### Datapath & Control Path

The diagram shows how processor components are interconnected and how data flows through the system.

<img width="1129" height="805" alt="Control Path Schematic" src="https://github.com/user-attachments/assets/43a5d250-cd1f-4570-ac31-1372fe2d4d63" />

---

## Hardware Implementation

<img width="1156" height="545" alt="Basys 3 FPGA" src="https://github.com/user-attachments/assets/64c19cda-5662-41df-9f2c-c51bfc9c03ed" />

The processor was implemented on the **Basys 3 FPGA board**.  

- Results are displayed using onboard LEDs.  
- Execution pattern:  
  - Starts with register `R1 = 0`.  
  - Executes `ADDI` repeatedly, incrementing values (1, 2, 4, 8, …, 128).  
  - After `128`, the `JMP` instruction executes, continuing values (129, 257, 513, …).  
  - This cycle repeats continuously.  

The board includes buttons for **reset** and **manual clocking**, enabling interactive control of execution.

---

## Summary
This project demonstrates the design and FPGA implementation of a **16-bit single-cycle processor**, supporting a basic instruction set with **arithmetic, logical, memory, and control flow operations**. It provides a foundational understanding of processor architecture and digital design using Verilog and Vivado.
