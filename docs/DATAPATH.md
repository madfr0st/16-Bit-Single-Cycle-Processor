# Datapath diagrams (all three cores)

This file is the picture-first companion to the RTL. Open the relevant
`rtl/cpu.v` side-by-side and trace each labelled wire.

- [scp16 datapath](#scp16-datapath)
- [x86lite32 datapath](#x86lite32-datapath)
- [armlite32 datapath](#armlite32-datapath)
- [Reading any datapath diagram](#reading-any-datapath-diagram)

---

## scp16 datapath

Width = 16. Every line below is a 16-bit bus unless annotated.

```
                                                            +-------------+
                                                            |             |
                                                +-----------+ +1: PC + 2  |
                            +------+            |           |             |
                            |      |            |  br_addr  +------+------+
   rst,inc,jmp,branch ----->| PC   |<--mux------+                  |
                            |      |            |  jmp_addr        |
                            +------+            |                  |
                                |               |                  |
                          pc_out|               |                  |
                                v               |                  |
                          +-----------+         |                  |
                          | InstrMem  |         |                  |
                          | (ROM, 1KB)|         |                  |
                          +-----------+         |                  |
                                |               |                  |
              instruction[15:0] |               |                  |
        +-----------+-----------+-------+       |                  |
        |           |           |       |       |                  |
        v           v           v       v       |                  |
   [15:12]opc   [11:8]rd     [7:4]rs  [3:0]imm  |                  |
        |           |           |       |       |                  |
        |           |           |       v       |                  |
        |           |           |  +--------+   |                  |
        |           |           |  | SignExt|---+----+             |
        |           |           |  +--------+        |             |
        |           v           v                    |             |
        |       +--------+--------+                  |             |
        |       |    RegFile      |                  |             |
        |       | 16 x 16, 2R/1W  |                  |             |
        |       +--------+--------+                  |             |
        |           |        |                       |             |
        |       data_rd  data_rs                     |             |
        |           |        |                       |             |
        v           |        |                       |             |
   +--------+       |        |                       |             |
   |Control |--->control sigs|                       |             |
   |  Unit  |    (8 wires)   |                       |             |
   +--------+                |                       |             |
        |                    |                       |             |
        |                    v                       |             |
        |             +-------------+                |             |
        |             |    ALU      |<--- sext_imm --+             |
        |             |  + branch   |                              |
        |             |  + jmp tgt  |---branch----------+          |
        |             +------+------+---result---+      |          |
        |                    |                   |      |          |
        |                    v                   v      |          |
        |             +-------------+      +----------+ |          |
        |             |  DataMem    |      |          | |          |
        |             |  (async R,  |      |  WB MUX  |-+(to RF)   |
        |             |   sync  W)  |      |          |            |
        |             +------+------+      +----------+            |
        |                    |                                     |
        |                mem_out                                   |
        |                    +---------------------------+         |
        +-------------------- (branch / jmp target back to PC)-----+
```

**Critical path** (longest combinational chain in a single clock):

```
clk -> PC.Q -> IM -> control_unit + sign_extend
            -> RF.read
            -> ALU
            -> DM (LW path)
            -> writeback MUX
            -> RF.D
```

**Control-signal flow per instruction class:**

| Class    | reg_we | mem_re | mem_we | mux_sel | immi_en | jmp | alu_op  |
|----------|:------:|:------:|:------:|:-------:|:-------:|:---:|:-------:|
| R-type   | 1      | 0      | 0      | 0       | 0       | 0   | funct   |
| LW       | 1      | 1      | 0      | 1       | 1       | 0   | ADD     |
| SW       | 0      | 0      | 1      | 0       | 1       | 0   | ADD     |
| ADDI     | 1      | 0      | 0      | 0       | 1       | 0   | ADD     |
| BEQ      | 0      | 0      | 0      | 0       | 1       | 0   | SUB-cmp |
| BNE      | 0      | 0      | 0      | 0       | 1       | 0   | SUB-cmp |
| JMP      | 0      | 0      | 0      | 0       | 0       | 1   | (don't care)  |

---

## x86lite32 datapath

Width = 32. The new boxes vs scp16 are **FlagsReg** and an **ESP side-port**
on the regfile.

```
              +------+                       +--------------+
   rst ------>|      |<--branch_taken,target-|  next-PC     |
              | PC32 |<--is_ret,ret_target---|  priority    |
              |      |                       +------+-------+
              +------+                              |
                  |                                 |
                pc_out (32)                         |
                  v                                 |
            +-----------+                           |
            | InstrMem  |                           |
            +-----------+                           |
                  |                                 |
        instruction[31:0]                           |
   +-----+--------+--------+---------+              |
   |     |        |        |         |              |
   v     v        v        v         v              |
 op8    dst4    src4     imm16                      |
   |     |        |        |                        |
   v     |        |        v                        |
+------+ |        |   +---------+                   |
| CU   | |        |   |SignExt  |----------+        |
| 17 sig| |        |   +---------+         |        |
+--+--+ |        |                         |        |
   |    v        v                         v        |
   |  +-----------------+   +----------------+      |
   |  |    RegFile      |<--|    ESP side    |      |
   |  | 16x32  2R/1W +  |   |    +-/+4 mux   |      |
   |  | ESP side port   |   +----------------+      |
   |  +---+----+----+---+                           |
   |   dst32 src32 esp32                            |
   |     |    |    |                                |
   |     v    v    |                                |
   |   +--------+  |                                |
   |   | ALU op |--+                                |
   |   |  ADD/SUB/AND/OR/XOR/SHL/SHR/SAR/PASS/NEG/NOT|
   |   +--+----+---+                                |
   |      |    |                                    |
   |  result   flags_next                           |
   |      |        |                                |
   |      v        v                                |
   |  +-----+   +--------+                          |
   |  | mem |   |FlagsReg|--cond_e/ne/g/l/ge/le-----+
   |  | addr|   | (4-bit |
   |  | mux |   |  OSZC) |
   |  +--+--+   +--------+
   |     |
   |     v
   |  +-----------+
   |  |  DataMem  |  (combinational read, sync write)
   |  +-----+-----+
   |        |
   |    mem_rdata
   |        |
   |   +---------+
   |   | WB MUX  |--> wr_data into RF
   |   +---------+
```

**Critical path:**

```
clk -> PC.Q -> IM -> CU + sext + RF.read -> ALU -> [DM for LD/POP/RET]
                                                -> WB mux -> RF.D
            (parallel: FlagsReg -> cond predicate -> next-PC mux)
```

**Conditional-jump decision:**

```
                cond_code (from CU)
                       |
              +--------v---------+
   cond_e --->|                  |
   cond_ne -->|                  |
   cond_g --->|     6:1 MUX      |--cond_match
   cond_l --->|                  |          |
   cond_ge -->|                  |          v
   cond_le -->|                  |     +---------+
              +------------------+     | AND     |--branch_taken
                                       +---------+
   is_cond_jump (from CU)  -->-------- |
   is_jump      (from CU)  -->-------- OR ---->
```

---

## armlite32 datapath

Width = 32. The new structural elements vs x86lite32 are the **barrel
shifter** for Operand2 and the **cond_unit** gating every write.

```
              +-----------+
   rst ------>|           |<--branch_taken,target
              |   PC32    |<--pc_we_from_rf, rf_pc_data
              +-----------+
                    |
                  pc (32)
                    |
                    v
              +-----------+
              | InstrMem  |
              +-----------+
                    |
            instruction[31:0]
              |
   +----------+--+----+----+----+----+----+----+---------+
   |             |    |    |    |    |    |    |         |
   v             v    v    v    v    v    v    v         v
 cond4    type3 op4 S Rn   Rd   shamt sh  Rm    imm_rot/imm8 / imm12 / br24
   |              \  |  \  |    |        / /
   |               \ |   \ |    |       / /
   |                \v    \v    v      v v
   |              +---------------------------+
   |              |        Control Unit       |--> is_dp_imm, is_dp_reg,
   |              +-------------+-------------+    is_load/store, is_branch,
   |                            |                  dp_opcode, set_flags, ...
   |                            v
   |                  +-------------------+
   |                  |     RegFile       |
   |                  |  16x32 + R15<-PC  |--rn_data, rm_data
   |                  +-------------------+
   |                            |
   |                            v
   |                  +-------------------+
   |                  | Barrel Shifter    |
   |                  |  (Op2 generator,  |--op2 (32)
   |                  |   imm rot OR      |
   |                  |   reg shifted)    |
   |                  +-------------------+
   |                            |
   |                            v
   |                  +-------------------+
   |                  |       ALU         |
   |                  |  16 ops + NZCV    |
   |                  +---+--------+------+
   |                      |        |
   |                   result   flags_next
   |                      |        |
   |                      v        v
   |                  +------+  +--------+
   |                  | DM   |  | CPSR   |---N,Z,C,V
   |                  | LDR/ |  | (NZCV) |
   |                  | STR  |  +--------+
   |                  +--+---+      |
   |                     |          v
   |                     v       +--------+
   |                  +--------+ |cond_u  |----+
   |                  |  WB    | |        |    |
   |                  | mux    | +--------+    |
   |                  +---+----+               v
   |                      |              (gates every write)
   |                      v
   v                    wr_data
+--------+
|cond_u  |----cond_execute (gates ALL writes & branch)
|        |
+--------+
```

**Critical path:**

```
clk -> PC -> IM -> CU + sext24 + RF.read -> barrel_shifter -> ALU
                                       -> [DM for LDR]
                                       -> WB mux
                                       -> RF.D
            (parallel: CPSR -> cond_unit.execute, gates writes)
```

---

## Reading any datapath diagram

Three habits make any datapath instantly more readable:

1. **Identify the register edges.** Everything between two flip-flops is
   combinational. The clock period must be longer than the longest such
   chain. Spot every box that ends with "Reg" or has a clock arrow.

2. **Identify the muxes.** Every mux corresponds to a control signal. Every
   control signal corresponds to a row in the control-unit's case statement.
   If you can match `cpu.v`'s mux selects to the CU's outputs by hand, you
   understand the design.

3. **Trace one instruction.** Pick any instruction, walk its values along
   the wires, and make sure the writeback at the next edge lands where you
   expect. If you can do that for ADD, LW, and a taken branch, you can do it
   for anything.

The world's most complex CPUs (Intel, Apple M1) are 100,000x bigger but
follow the exact same rules at every flip-flop. The diagrams are just
denser.
