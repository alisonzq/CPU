# 16-bit CPU: Logisim → Verilog Port

This document records the process of porting a 16-bit CPU, originally built as a Logisim-evolution
circuit (`cpu.circ`) for a computer architecture lab, into synthesizable Verilog targeting the
Vivado/Quartus FPGA toolchain. The port was done task-by-task, mirroring the five tasks of the
original lab, with every module written by hand and verified in simulation against the lab's test data before moving on to the next task.

<img width="1518" height="741" alt="image" src="https://github.com/user-attachments/assets/591fc061-4c2d-4416-9653-43c0ae1319c9" />

## How this port was done

Every RTL module (`alu.v`, `registerfile.v`, `control_fsm.v`, `ins_mem.v`, `data_mem.v`,
`condition_encoding.v`, `cpu.v`) was written from scratch, not auto-translated from the `.circ` file.
Each draft was reviewed against the original circuit's structure and the lab's real golden traces,
bugs were itemized with concrete fixes, and only once a task's modules passed its own test data did
the next task begin. All five tasks now pass end-to-end against every test file the lab provided.

## Architecture summary

- 16-bit data width throughout (registers, ALU, memory words, instructions).
- 8 general-purpose registers (`R0`-`R7`), `R0` is a normal writable register (not hardwired to zero).
- Non-pipelined, strictly sequential 5-stage FSM: one instruction fully completes all five stages
  before the next one begins. Because of this, `IR`/`RA`/`RB` stay frozen across DECODE-MEMORY,
  which is what lets several design choices below work out consistently.
- 64K x 16-bit instruction memory and 64K x 16-bit data memory, each modeled as a `reg [15:0] mem [0:65535]`
  array.
- Debug output `cpu_out` is a fixed 48-bit concatenation `{PC, IR, RZ}` (bits 47:32 / 31:16 / 15:0) that
  never changes shape across any task.
- Halt condition: `IR == 16'h4380`, which decodes to `BEQ -1, R0, R0` (a self-branch, i.e. an infinite
  loop on its own address) - purely combinational, and the same sentinel is used by every test program
  in the lab to mark "end of simulation."

### FSM states

| State      | Encoding | What happens |
|------------|----------|---------------|
| FETCH      | `3'b000` | `IR <= instr_word`, `PC <= PC + 1` (or branch target) |
| DECODE     | `3'b001` | `RA <= regfile_A`, `RB <= regfile_B` |
| EXECUTE    | `3'b010` | `RZ <= alu_c`, `RD <= RB` (forwards store data), branch target computed |
| MEMORY     | `3'b011` | `RW <= is_load ? data_word : RZ`; `data_mem` write enabled for stores |
| WRITEBACK  | `3'b100` | `rf_we` asserted only if the instruction actually writes back |

The state register is a plain `state + 1` wraparound back to FETCH.

### Instruction encoding (16 bits)

| Bits    | Field                        | Notes |
|---------|------------------------------|-------|
| `[15:14]` | Opcode                     | `00`=ALU, `01`=Branch, `10`=Load, `11`=Store |
| `[13:11]` | ALU op / Condition code    | ALU function select for ALU ops; condition code for Branch |
| `[10]`    | I-bit                      | `0` = register operand, `1` = immediate operand |
| `[9:7]`   | Dest reg / Data reg / Offset | ALU: destination register. Store: "data register" (read via the B port). Branch: **3-bit signed offset**, e.g. `-1` for the halt self-loop |
| `[6:4]`   | Src reg 1 / Addr reg 1 / Branch reg A | First operand / address register / first compared register |
| `[3:0]`   | Src op 2 / Addr imm         | 4-bit sign-extended immediate when `I`=1. In register mode (`I`=0), only the low 3 bits `[2:0]` select the second register. |

Branch instructions were confirmed (by hand-decoding real test data, e.g. `BGE 3, R1, 0` = `0x6d90` and
`BNE -4, R5, 0` = `0x4e50`) to reuse exactly the same bit positions as ALU/Load/Store - no new fields
were needed. The only wrinkle is that the "dest reg" field `[9:7]`, which has no meaning for a branch
(branches don't write back), is repurposed as a signed 3-bit branch offset, sign-extended to 16 bits
with `{{13{IR[9]}}, IR[9:7]}`.

## Module list

- **`alu.v`** - combinational 16-bit ALU: ADD, SUB, AND, OR, NOR, LSL, LSR, ASR, plus N/C/Z/V flags.
- **`registerfile.v`** - 8x16 register file, synchronous write, combinational read (two read ports).
- **`control_fsm.v`** - the 5-state FSM described above; owns every `*_we` control signal in the
  datapath. Takes two datapath-computed conditions as inputs (`writes_back`, `is_branch_taken`) so it
  can gate `rf_we` and the EXECUTE-stage `pc_we` correctly without knowing instruction semantics itself.
- **`ins_mem.v`** - 64K x 16 instruction memory, combinational read, optional `$readmemh` load via a
  `MEM_FILE` parameter.
- **`data_mem.v`** - 64K x 16 data memory, combinational read, synchronous (nonblocking) write. No
  `reset` port, matching the original circuit's RAM configuration ("Use clear pin: No").
- **`condition_encoding.v`** - combinational branch condition evaluator (`EQ`/`NE`/`LT`/`LE`/`GT`/`GE`)
  from the ALU's `Z`/`N`/`V` flags, using the standard signed two's-complement comparison scheme
  (`LT` = `N != V`, etc.).
- **`cpu.v`** - top-level datapath: instantiates all of the above, decodes instruction fields, and owns
  the six architectural registers `PC, IR, RA, RB, RZ, RW, RD`.

## Task-by-task build log

### Task 1 - ALU

Verified against a 28-vector test table covering every operation and flag combination. Bugs found and
fixed along the way:

- Missing `end` keywords after the ADD/SUB `begin` blocks (syntax error).
- A missing `OP_NOR` case entirely.
- Shift amount read from `B[4:0]` instead of the spec's `B[3:0]` (caught by test vectors specifically
  designed to expose bit-4 leakage).
- SUB's carry flag came out inverted relative to the expected "NOT borrow" convention. The first fix
  attempt, `A + (~B) + 1`, *still* produced the wrong carry - the real cause was Verilog's
  context-determined width propagation: `~B` was silently extended to 17 bits by the surrounding
  addition's width *before* being inverted. The actual fix forces self-determined widths via
  concatenation: `{carry, C} = {1'b0, A} + {1'b0, ~B} + 17'b1;`.

<img width="760" height="868" alt="image" src="https://github.com/user-attachments/assets/9fc5ecec-19d2-46c6-9408-737103632126" />

### Task 2 - Register File

Verified by replaying the exact 16-cycle stimulus extracted from the `.circ` file's own
`RegisterFileTester` ROMs. Bugs fixed:

- A typo, `registers[Addr+C]`, should have been `registers[Addr_C]`.
- The `A`/`B` read-port outputs were never actually driven (missing `assign`).
- An incorrect guard hardwired `R0` to zero on writes (`we && Addr_C != 3'b0`); the spec and the
  RegisterFileTester's own gold data both confirm `R0` is a normal, fully writable register.

<img width="713" height="696" alt="image" src="https://github.com/user-attachments/assets/7c0a962c-d31e-41a3-97ee-b1b7d84270cb" />

### Task 3 - Basic programmable CPU (ALU instructions only)

Built `control_fsm.v`, `ins_mem.v`, and the first version of `cpu.v`. Verified 17/17 `cpu_out`
transitions against `aluinstrtest.rom`/`.out`. Notable bugs along the way: an FSM draft that crammed
everything into a single combinational block with no clocked state register at all; a later draft that
left a stray state-update line inside the combinational block, creating a zero-delay combinational loop
(`Iteration limit reached at time 0 ps`); 17-bit register widths that should have been 16; the ALU's B
input wired straight to `RB` instead of through the immediate/register mux; and several missing
semicolons/commas in module instantiations.

### Task 4 - Data memory and load/store instructions

Built `data_mem.v` and extended `cpu.v`/`control_fsm.v` for Load/Store. Verified 70/70 transitions
against each of `linklisttest1` and `linklisttest2` (a real singly-linked-list traversal test - not
just straight-line arithmetic). Key design resolution: the FSM's control table asserts `rd_we` in
EXECUTE and `rw_we` in MEMORY, which only works because `data_mem` is addressed by the *live*
combinational `alu_c`, not the registered `RZ` - since `RA`/`RB` are frozen from DECODE through MEMORY
in this non-pipelined design, `alu_c` stays valid the whole time, letting the RAM's read/write start a
cycle "early" without needing a fourth address register. Bugs fixed:

- `data_mem`'s address was wired to `PC` instead of `alu_c`.
- `data_mem`'s write data was wired to `RZ` instead of `RD` (the value has to be forwarded one cycle,
  since by the time the store's memory access happens, `RB` has already been overwritten by DECODE of
  whatever comes next in some drafts).
- A blocking assignment (`mem[addr] = data_in;`) inside `data_mem`'s clocked write block, which breaks
  the "write takes one cycle" semantics real synchronous RAM has - fixed to nonblocking (`<=`).
- A broken hand-rolled write-enable latch with a missing `else`, causing memory corruption after the
  first store - replaced with a direct combinational `.we(is_store && rw_we)`.
- `addr_b_sel` implicitly declared as a 1-bit wire (silent truncation) instead of `[2:0]`.

### Task 5 - Branching

Built `condition_encoding.v` and extended `control_fsm.v` (new `is_branch_taken` input, EXECUTE-stage
conditional `pc_we`) and `cpu.v` (branch target computation, ALU-op override to force SUB for
comparisons, condition-code evaluation). Verified against all four `multiplication1-4` tests - a real
shift-add multiply routine with backward-taken branches, so `cpu_out`'s `PC` field does *not* increase
monotonically in these golden traces, unlike every earlier task. Final results: 60/60, 53/53, 41/41,
48/48 transitions matched. Bugs fixed:

- **Dangling-else bug in the PC update block.** An early draft wrapped only the `if (is_branch_taken)`
  arm in a `begin...end` that closed *before* the trailing `else`, so that `else` silently re-attached
  to the outer `if (reset)/else if (pc_we)` chain instead of the intended inner `if`. Net effect: PC
  never advanced on ordinary FETCH cycles, but incremented every single clock during DECODE/MEMORY/
  WRITEBACK. Fixed by wrapping the *entire* inner `if/else` pair in one `begin...end`.
- **Stale-`IR`-during-FETCH double branch.** `is_branch_taken` was computed straight from `IR`, but
  during the FETCH state `IR` still holds the *previous* instruction until the FETCH→DECODE clock edge.
  Since `pc_we` is also unconditionally high during FETCH, the branch-target arm of the PC mux was
  firing a second time - using the *previous* branch's offset - immediately after any taken branch,
  corrupting `PC` (observed directly: a correct branch 2→5, followed by an incorrect 5→8 using the same
  +3 offset again, instead of the expected 5→6). Fixed by gating branch-taken with `rz_we`, which is
  asserted only during EXECUTE: `wire is_branch_taken = is_branch && cond_result && rz_we;`. This is the
  same principle every other IR-derived decode signal in the design already follows implicitly (they're
  only ever acted on during DECODE-WRITEBACK, when `IR` is guaranteed current) - `is_branch_taken` was
  the one signal that also had an effect during FETCH, so it needed the same protection made explicit.
- `condition_encoding.v`'s `case` statement had no `default`, which would infer a latch for the two
  unused 3-bit condition codes; added `default: C = 1'b0;`. It also originally used nonblocking (`<=`)
  assignment inside a combinational `always @(*)` block - not a functional bug in isolation, but
  inconsistent with the rest of the design's convention, so cleaned up to blocking (`=`).
<img width="705" height="374" alt="image" src="https://github.com/user-attachments/assets/79c47962-cba3-42c9-b7df-4902c8fe11f9" />

## Testing methodology

Every task was validated the same way, against the lab's own real golden data - never invented test
cases:

1. **Golden traces are change logs, not per-cycle dumps.** Each `.out` file only gets a new row when
   `cpu_out` actually changes value: Fetch changes `PC`/`IR`, Execute changes `RZ`; Decode/Memory/
   Writeback never touch `cpu_out`, so they never add a row. All testbenches sample `cpu_out` every
   clock but only check it against the next expected row on an actual change.
2. **ROM contents are loaded via hierarchical poke, not `$readmemh`.** The simulator in use here had
   working-directory issues resolving `$readmemh` file paths from the GUI, so every testbench instead
   pokes instruction words directly into the instruction memory's internal array from an `initial`
   block at time 0 (`dut.imem_inst.mem[i] = 16'hXXXX;`), bypassing file I/O entirely.
3. **Self-checking, not eyeballed.** Every testbench decodes the real `.out` file into a `reg [47:0]
   expected[]` array and a real `.rom` file into hierarchical pokes, then runs a
   `while (!halt && cycle_count < MAX_CYCLES)` loop that fails loudly (with cycle number, expected
   value, and actual value) on any mismatch, and also fails if the number of `cpu_out` changes doesn't
   match the golden row count, or if `halt` never asserts within the timeout.

Test files delivered and their final results:

| Test | Instructions | Golden rows | Result |
|------|-------------|-------------|--------|
| `tb_alu.v` | 28 vectors | - | All passed |
| `tb_registerfile.v` | 16-cycle replay | - | All passed |
| `tb_cpu_alu.v` (Task 3) | 9 | 17 | 17/17 |
| `tb_cpu_linklist1.v` (Task 4) | 41 | 70 | 70/70 |
| `tb_cpu_linklist2.v` (Task 4) | 42 | 70 | 70/70 |
| `tb_cpu_mult1.v` (Task 5) | 26 | 60 | 60/60 |
| `tb_cpu_mult2.v` (Task 5) | 26 | 53 | 53/53 |
| `tb_cpu_mult3.v` (Task 5) | 26 | 41 | 41/41 |
| `tb_cpu_mult4.v` (Task 5) | 26 | 48 | 48/48 |

## Verilog lessons that came up repeatedly

- **Blocking (`=`) vs. nonblocking (`<=`):** nonblocking belongs in every clocked
  (`always @(posedge clk)`) block, to correctly model all registers updating "simultaneously" from
  their pre-edge values, the way real flip-flops behave. Blocking belongs in combinational
  (`always @(*)`) blocks, where top-to-bottom, immediate evaluation is exactly what's wanted. Using
  blocking assignment for `data_mem`'s write was the clearest example of what goes wrong when this is
  mixed up: it broke read-during-write timing.
- **`wire` vs. `reg` is about *how* a signal is driven, not what it physically is.** A signal driven by
  a continuous `assign` is a `wire`. A signal written inside any procedural (`always`/`initial`) block -
  combinational or clocked - must be declared `reg`, even if it has no actual memory (e.g. every
  `always @(*)` output in `alu.v` and `control_fsm.v`). A submodule's output port always connects to a
  `wire` in the parent, regardless of whether that port is `reg` or `wire` internally - the reg/wire
  choice never crosses a module boundary.
- **Context-determined width propagation.** Operators like `~`, `+`, `-` are context-determined and
  will silently extend their operands to match the width of the surrounding expression *before*
  applying the operator - this is what caused the SUB carry-flag bug twice. Concatenation
  (`{1'b0, X}`) forces self-determined width and sidesteps the problem.
- **The dangling-else trap.** In `if (cond) begin ... end else ...`, the `begin`/`end` placement -not
  indentation- decides which `if` an `else` binds to. An inner `if` without its own `else`, sitting
  inside a `begin...end` that closes right after it, will silently hand the next `else` to the
  *outer* `if` instead.
- **Signals that are valid everywhere except one specific state.** Any signal decoded from `IR` is only
  guaranteed current from DECODE through WRITEBACK, not during FETCH (where `IR` still holds the
  previous instruction until the clock edge). Signals that are only *acted on* during DECODE-WRITEBACK
  (the vast majority) never notice this. `is_branch_taken` was the one exception, because it also
  affects the FETCH-stage `PC` update - which is why it needed to be explicitly masked with `rz_we`.
- **Zero-delay combinational loops.** A signal read and written within the same `always @(*)` block
  with no intervening clocked register produces `Iteration limit reached at time 0 ps` in simulation -
  always trace this back to a combinational block that's missing its clocked counterpart.

## Toolchain notes

The target toolchain for this project is Vivado/Quartus, but all verification during development was
done with ModelSim. Every module here is written in plain,
synthesizable Verilog with no simulation-only constructs in the RTL itself (`$readmemh` is optional and
parameterized off by default; the hierarchical-poke trick lives entirely in the testbenches, never in
the DUT).

## Suggested next steps

- Synthesize each module (or the full `cpu.v` hierarchy) in Vivado/Quartus and resolve any synthesis
  warnings - in particular, double-check there are no inferred latches now that `condition_encoding.v`
  has its `default` case.
- Add I/O: a way to actually observe `cpu_out` on hardware (seven-segment display, UART, or onboard
  LEDs for a subset of bits), plus a reset button/switch mapped to the `reset` input.
- Timing closure: constrain the clock and check that the combinational path through `alu_c` →
  `data_mem` (address) → `data_out` and the `alu_c` → `condition_encoding` → `is_branch_taken` →
  `control_fsm` → `pc_we` path both meet timing at the target clock frequency, since both are longer
  combinational chains than a typical single-cycle path.
- Consider adding a hardware smoke test (blink an LED after `halt` asserts) before trying to load a full
  test program via BRAM initialization on the actual board.
  Pipelining. The current design is strictly sequential - one instruction fully completes all five stages before the next one starts - and several of the design choices documented above (data_mem addressed by live alu_c instead of RZ; IR/RA/RB treated as frozen from DECODE through MEMORY) rely on exactly that non-overlap. Turning this into a true 5-stage pipeline (overlapping Fetch/Decode/Execute/Memory/Writeback of consecutive instructions) would need real hazard handling that this version currently gets for free: data hazards (a RAW hazard when an instruction reads a register that a still-in-flight earlier instruction hasn't written back yet, needing forwarding paths instead of just reading the register file), control hazards (a branch's outcome isn't known until its own EXECUTE stage, by which point later stages will have already fetched one or more wrong-path instructions - needing either a pipeline flush/bubble on every taken branch or a branch predictor), and structural hazards if ins_mem/data_mem ever need to be accessed by two instructions in the same cycle. The stale-IR-during-FETCH bug found in Task 5 is a preview of the kind of hazard that shows up everywhere once stages actually overlap - a pipelined redesign would need a proper hazard detection unit rather than the single targeted rz_we gate used here.
