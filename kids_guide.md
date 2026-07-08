# Simple Step-by-Step Kid Guide to Build Your First Blocks

This guide will hold your hand through every single step. We will build your first designs today using your local AI model.

---

## Part 1: Files to Put on GitHub
Upload the following files to your GitHub repository so you can download or reference them anywhere. These are the absolute full paths:

### The Rules & Checklists
1. `D:\design_plans\ai-hw-os\AGENTS.md` 
   *(Note: This file is the rulebook for coding agents like Aider or Qwen. They read it automatically when they open the folder. You do not need to copy-paste this when prompting).*
2. `D:\design_plans\ai-hw-os\00_profile\task_contract_template.md` (The behavior contract)
3. `D:\design_plans\ai-hw-os\06_rtl_design_patterns\skill_rtl_module_generation.md` (The RTL generation recipe)
4. `D:\design_plans\ai-hw-os\07_validation_patterns\skill_testbench_planning.md` (The testbench planning recipe)
5. `D:\design_plans\ai-hw-os\13_cheatsheets\CHEATSHEET_rtl_design_gotchas.md` (Common hardware mistakes to avoid)

### The Exemplar Code (Perfect Examples to Copy)
6. `D:\design_plans\ai-hw-os\22_gold_standard\rtl\evt_counter.sv` (How good RTL should look)
7. `D:\design_plans\ai-hw-os\22_gold_standard\tb\tb_evt_counter.sv` (How a good testbench should look)

### The Spec Sheets (What the blocks must do)
8. `D:\design_plans\01_common_ip.md` (The leaf specs table)
9. `D:\design_plans\narratives\01_common_ip_narrative.md` (The leaf specs explained in plain words)
10. `D:\design_plans\06_verification_plan.md` (The testbench requirements matrix)

---

## Part 2: Step-by-Step to Build Your First Blocks (Prerequisites)

We will build the **LFSR32** (random data maker) and the **MISR32** (result checker) first. Both systems need these blocks!

### Step 1: Create a Folder
On your Windows computer, create a new folder here:
`D:\design_plans\pnp_ip\lfsr_misr`

---

### Step 2: Make `lfsr32.sv` (RTL)
1. Open a **brand new chat session** with your local AI model (7B Coder).
2. Copy the entire contents of these five files and paste them into the chat:
   - `D:\design_plans\ai-hw-os\00_profile\task_contract_template.md`
   - `D:\design_plans\ai-hw-os\06_rtl_design_patterns\skill_rtl_module_generation.md`
   - `D:\design_plans\ai-hw-os\13_cheatsheets\CHEATSHEET_rtl_design_gotchas.md`
   - `D:\design_plans\ai-hw-os\22_gold_standard\rtl\evt_counter.sv`
   - `D:\design_plans\pnp_ip\axis_src_sink\axis_src_sink.sv` (Exemplar reference)
3. Copy and paste the spec below into the chat:
```markdown
DESIGN SPEC: lfsr32 — seeded pseudo-random stimulus generator
Parameters: WIDTH = 32
Ports:
- input logic clk
- input logic rst (synchronous active-high reset)
- input logic load (load seed this cycle, wins over enable)
- input logic [31:0] seed (loaded on load)
- input logic enable (advance LFSR state right one step per cycle when high)
- output logic [31:0] prdata (registered state)
- output logic valid (registered enable, high 1 cycle after a shift/advance)

Function behavior:
- Sync active-high reset 'rst' sets 'prdata' state to 32'h1 and 'valid' to 0.
- When 'load' is high, set 'prdata' directly to 'seed'. If 'seed' is 0, replace it with 32'h1 to avoid locking up.
- When 'enable' is high (and 'load' is low), shift 'prdata' right by 1. If the LSB (bit 0) was 1, XOR 'prdata' with the tap polynomial 32'h80200003.
- WARNING: The template file 'axis_src_sink.sv' has a function 'lfsr32_next' that shifts LEFT. Do NOT copy that! You must shift RIGHT (Galois style) as described here.
- 'valid' goes high for one cycle on the clock following a shift/advance (not on a load).
```
4. Type this command to the AI:
   **"Generate SystemVerilog code for the lfsr32 module based on the spec,gotchas cheatsheet, and rules above. Make sure it shifts right, not left."**
5. Save the output code in a file named:
   `D:\design_plans\pnp_ip\lfsr_misr\lfsr32.sv`

---

### Step 3: Make `misr32.sv` (RTL)
1. Open another **brand new chat session** with your local AI model (7B Coder).
2. Copy the entire contents of these five files and paste them into the chat:
   - `D:\design_plans\ai-hw-os\00_profile\task_contract_template.md`
   - `D:\design_plans\ai-hw-os\06_rtl_design_patterns\skill_rtl_module_generation.md`
   - `D:\design_plans\ai-hw-os\13_cheatsheets\CHEATSHEET_rtl_design_gotchas.md`
   - `D:\design_plans\ai-hw-os\22_gold_standard\rtl\evt_counter.sv`
   - `D:\design_plans\pnp_ip\axis_src_sink\axis_src_sink.sv` (Exemplar reference)
3. Copy and paste the spec below into the chat:
```markdown
DESIGN SPEC: misr32 — signature compressor
Parameters: WIDTH = 32
Ports:
- input logic clk
- input logic rst (sync active-high reset, clears signature to 0)
- input logic clear (sync clear, clears signature to 0)
- input logic valid (compress data this cycle)
- input logic [31:0] data (input word)
- output logic [31:0] signature (registered current signature)

Function behavior:
- Sync active-high reset 'rst' and 'clear' set 'signature' to 32'h0.
- Each cycle 'valid' is high, calculate:
  signature <= {signature[30:0], feedback} ^ data;
  where feedback = signature[31] ^ signature[21] ^ signature[1] ^ signature[0].
- If 'valid' is low, signature remains unchanged.
- HINT: The mathematical feedback signature loop is identical to the one in `axis_sig_sink` inside `axis_src_sink.sv`, but note that our reset and clear are synchronous active-high and set the signature to 32'h0 (not 32'hFFFF_FFFF).
```
4. Type this command to the AI:
   **"Generate SystemVerilog code for the misr32 module based on the spec and rules above. You can reference the math from axis_src_sink.sv, but make sure to use active-high resets and clears."**
5. Save the output code in a file named:
   `D:\design_plans\pnp_ip\lfsr_misr\misr32.sv`

---

### Step 4: Make the Testbench (`tb_lfsr_misr.sv`) and C model (`golden.c`)
1. Open a **brand new chat session** with your local AI model (14B or 27B).
2. Copy the entire contents of these three files and paste them into the chat:
   - `D:\design_plans\ai-hw-os\00_profile\task_contract_template.md`
   - `D:\design_plans\ai-hw-os\07_validation_patterns\skill_testbench_planning.md`
   - `D:\design_plans\ai-hw-os\22_gold_standard\tb\tb_evt_counter.sv`
3. Paste the contents of your newly generated `lfsr32.sv` and `misr32.sv` files into the chat.
4. Copy and paste this prompt to the AI:
```markdown
Write a unified self-checking SystemVerilog testbench 'tb_lfsr_misr.sv' and its companion C model 'golden.c' (using DPI-C) to verify the 'lfsr32' and 'misr32' modules.
Requirements:
1. golden.c must implement:
   - 'int dpi_lfsr32_next(int state)' which shifts state right by 1, XORs with 0x80200003 if LSB was 1, and substitutes 0x1 if state is 0.
   - 'int dpi_misr32_next(int sig, int data)' which shifts sig left, feeds back bit 31^21^1^0, and XORs data.
2. tb_lfsr_misr.sv must:
   - Instantiate 'lfsr32' and 'misr32'.
   - Generate a 10ns clock and hold active-high 'rst' for 5 cycles.
   - Loop through 3 random seeds. For each seed, load it into lfsr32, enable it, run for 10,000 cycles, feed the resulting prdata (when valid is high) into misr32, and check both outputs against the DPI C golden model every cycle.
   - Trigger a $fatal watchdog if simulation hangs past 100,000 steps.
   - Print a single '*** PASS ***' or '*** FAIL ***' banner with mismatch counts at the end.
```
5. Save the C code in a file named:
   `D:\design_plans\pnp_ip\lfsr_misr\golden.c`
6. Save the testbench code in a file named:
   `D:\design_plans\pnp_ip\lfsr_misr\tb_lfsr_misr.sv`

---

### Step 5: Run the Simulation & HW Validation
1. Click the Start Menu on your computer, type **PowerShell**, and open it.
2. Type these exact commands one line at a time and press Enter:
   ```powershell
   cd D:\design_plans\pnp_ip
   powershell -ExecutionPolicy Bypass -File scripts\run_sim.ps1 lfsr_misr
   ```
3. Look at the output in the window. It must print:
   `*** PASS: tb_lfsr_misr, 0 errors ***`

#### 🔌 Protium Emulator HW Validation (How to verify on the board):
* **LFSR32 Standalone Bring-Up:**
  * **ForceNet (Inputs to force/deposit):** `seed[31:0]` (deposit `32'h1`), `load` (pulse `0 -> 1 -> 0`), `enable` (force `1`).
  * **TriggerNet (Events to capture):** `valid` rising edge.
  * **MonitorNet (Nets to watch):** `prdata[31:0]`, `valid`.
  * **PASS Criteria:** `prdata` shifts through the seed-based pseudo-random sequence; does not lock at all-zeros.
* **MISR32 Standalone Bring-Up:**
  * **ForceNet:** `data[31:0]` (deposit inputs), `valid` (force `1`), `clear` (pulse `0 -> 1 -> 0`).
  * **TriggerNet:** `valid` rising edge.
  * **MonitorNet:** `signature[31:0]`.
  * **PASS Criteria:** `signature` updates on every clock cycle `valid` is high; clear sets signature to `32'h0`.

---
---

## Part 3: Build System 1 (ALINK-Mini — AXI Register Loopback with Chiplets)
*This is a complete 2-chiplet system (Master Chiplet and Slave Chiplet). We connect them directly over AXI4-Lite to test register read/writes. To drive it, we include a simplified `cmd_gen` inside the Master Chiplet that only executes register-checks, bypassing memory checks, so the system runs automatically with 0 errors.*

### Step 1: Create a Folder
Create a folder here:
`D:\design_plans\pnp_ip\alink_mini`

### Step 2: Copy Reused Bricks
Copy the LFSR and MISR blocks you built in Part 2 into this new folder:
- Copy `D:\design_plans\pnp_ip\lfsr_misr\lfsr32.sv` -> `D:\design_plans\pnp_ip\alink_mini\lfsr32.sv`
- Copy `D:\design_plans\pnp_ip\lfsr_misr\misr32.sv` -> `D:\design_plans\pnp_ip\alink_mini\misr32.sv`

### Step 3: Make `cmd_gen_mini.sv` (The Automated Tester FSM)
1. Open a **brand new chat session** with your local model (14B).
2. Paste the contents of these files:
   - `D:\design_plans\ai-hw-os\00_profile\task_contract_template.md`
   - `D:\design_plans\ai-hw-os\06_rtl_design_patterns\skill_rtl_module_generation.md`
   - `D:\design_plans\ai-hw-os\13_cheatsheets\CHEATSHEET_rtl_design_gotchas.md`
3. Copy and paste this prompt:
```markdown
Write the RTL module `cmd_gen_mini` which acts as the automated master tester. 
It instantiates two `lfsr32` blocks and one `misr32` block.
Ports:
- input logic clk, rst
- input logic go (1-clk pulse starts test)
- input logic [31:0] seed
- output logic cmd_valid, cmd_write, output logic [15:0] cmd_addr, output logic [32:0] cmd_wdata
- input logic cmd_ready
- input logic rsp_valid, input logic [31:0] rsp_rdata, input logic rsp_err
- output logic done (latched high when finished)
- output logic [7:0] err_cnt
- output logic [31:0] chk_sig

State Machine (FSM):
- IDLE: waits for go. When go is high, sample seed. Go to P3_REG.
- P3_REG: Write and read back registers in this order:
  1. Write SCRATCH0 (address 0x04) = 32'h5A5A_A5A5.
  2. Read SCRATCH0. Verify readback data is 32'h5A5A_A5A5. If not, err_cnt++.
  3. Write SCRATCH1 (address 0x08) = 32'hC3C3_3C3C.
  4. Read SCRATCH1. Verify readback data is 32'hC3C3_3C3C. If not, err_cnt++.
  5. Read ID (address 0x00). Verify readback data is 32'hA11C_0001. If not, err_cnt++.
  6. Read WRCNT (address 0x0C). Verify readback data is 32'd2 (since we did 2 successful writes).
  - Feed every readback data word into the internal misr32 on the cycle rsp_valid is high.
- DONE: Set done=1. chk_sig outputs the misr32 signature.
```
4. Save the code as:
   `D:\design_plans\pnp_ip\alink_mini\cmd_gen_mini.sv`

### Step 4: Make `axm_engine.sv` (AXI Master Driver)
1. Open a **brand new chat session** with your local model (14B).
2. Paste the contents of these files:
   - `D:\design_plans\ai-hw-os\00_profile\task_contract_template.md`
   - `D:\design_plans\ai-hw-os\06_rtl_design_patterns\skill_rtl_module_generation.md`
   - `D:\design_plans\ai-hw-os\13_cheatsheets\CHEATSHEET_rtl_design_gotchas.md`
3. Copy and paste this prompt:
```markdown
Write the RTL module `axm_engine` per the spec from D:\design_plans\11_alink_axi.md lines 98-130. 
Ports:
- input logic clk, rst (sync active-high reset)
- input logic cmd_valid, cmd_write, input logic [15:0] cmd_addr, input logic [32:0] cmd_wdata
- output logic cmd_ready
- output logic rsp_valid, output logic [31:0] rsp_rdata, output logic rsp_err
- AXI4-Lite master interface (awvalid, awready, awaddr[16], wvalid, wready, wdata[32], wstrb[4], bvalid, bready, bresp[2], arvalid, arready, araddr[16], rvalid, rready, rdata[32], rresp[2])

FSM rules:
- Idle: Wait for cmd_valid. If cmd_write, launch AW and W channels. If read, launch AR channel.
- Accept: Wait until slave handshakes AW/W/AR.
- Response: Wait for bvalid/rvalid, capture payload, output rsp_valid, return to idle.
- Timeout: If a transaction takes >256 cycles, abort and assert rsp_err.
```
4. Save the code as:
   `D:\design_plans\pnp_ip\alink_mini\axm_engine.sv`

### Step 5: Make `axs_regs.sv` (AXI Slave Registers)
1. Open a **brand new chat session** with your local model (7B Coder or 14B).
2. Paste the contents of these files:
   - `D:\design_plans\ai-hw-os\00_profile\task_contract_template.md`
   - `D:\design_plans\ai-hw-os\06_rtl_design_patterns\skill_rtl_module_generation.md`
   - `D:\design_plans\ai-hw-os\13_cheatsheets\CHEATSHEET_rtl_design_gotchas.md`
3. Copy and paste this prompt:
```markdown
Write the RTL module `axs_regs` per the spec from D:\design_plans\11_alink_axi.md lines 218-238.
Ports:
- input logic clk, rst (sync active-high reset)
- AXI4-Lite slave interface (awvalid, awready, awaddr[16], wvalid, wready, wdata[32], wstrb[4], bvalid, bready, bresp[2], arvalid, arready, araddr[16], rvalid, rready, rdata[32], rresp[2])
- output logic [31:0] scratch0, scratch1
- output logic [15:0] wrcnt

Registers map on lower byte addr[7:0]:
- 0x00: RO ID = 32'hA11C_0001
- 0x04: RW scratch0
- 0x08: RW scratch1
- 0x0C: RO WRCNT (counts accepted write operations to registers)
- Other addresses: return SLVERR (2'b10) response. Read unmapped returns 32'hDEADBEEF.
```
4. Save the code as:
   `D:\design_plans\pnp_ip\alink_mini\axs_regs.sv`

### Step 6: Make the Chiplets and Top wrappers
1. **axm_chiplet_mini.sv (Master Chiplet):** Open a fresh chat. Paste `cmd_gen_mini.sv` and `axm_engine.sv`. 
   *Prompt:* "Write a structural wrapper `axm_chiplet_mini` that instantiates `cmd_gen_mini` and connects it to `axm_engine`. Expose external ports: clk, rst, go, seed[32], done, err_cnt[8], chk_sig[32], and the AXI4-Lite master ports."
   *Save as:* `D:\design_plans\pnp_ip\alink_mini\axm_chiplet_mini.sv`

2. **axs_chiplet_mini.sv (Slave Chiplet):** Open a fresh chat. Paste `axs_regs.sv`.
   *Prompt:* "Write a structural wrapper `axs_chiplet_mini` that instantiates `axs_regs`. Expose the AXI4-Lite slave ports, scratch0[32], scratch1[32], and wrcnt[16]."
   *Save as:* `D:\design_plans\pnp_ip\alink_mini\axs_chiplet_mini.sv`

3. **alink_mini_top.sv (Top Design wrapper):** Open a fresh chat.
   *Prompt:* "Write a structural wrapper `alink_mini_top`. Instantiate `axm_chiplet_mini` and `axs_chiplet_mini`, connecting the AXI master ports directly to the AXI slave ports. Expose clk, rst, go, seed[32], done, err_cnt[8], chk_sig[32], scratch0[32], scratch1[32], and wrcnt[16]."
   *Save as:* `D:\design_plans\pnp_ip\alink_mini\alink_mini_top.sv`

### Step 7: Make `tb_alink_mini.sv` (Testbench)
1. Open a **brand new chat session** with your local model (14B).
2. Paste `alink_mini_top.sv`.
3. Copy and paste this prompt:
```markdown
Write a self-checking testbench `tb_alink_mini` for `alink_mini_top`.
Requirements:
1. Generate a 10ns clock and hold active-high 'rst' for 5 cycles.
2. Set seed = 32'h1234_5678.
3. Pulse 'go' high for one clock cycle.
4. Wait for output 'done' to go high. If it does not go high in 1,000 cycles, trigger $fatal (watchdog timeout).
5. Once 'done' is high, verify that err_cnt is 8'd0. Check that wrcnt reads 16'd2.
6. Print a final "*** PASS: tb_alink_mini, 0 errors ***" or *** FAIL *** banner.
```
4. Save the code as:
   `D:\design_plans\pnp_ip\alink_mini\tb_alink_mini.sv`

### Step 8: Run Sim & HW Validation for System 1
Run the following commands in PowerShell:
```powershell
cd D:\design_plans\pnp_ip
powershell -ExecutionPolicy Bypass -File scripts\run_sim.ps1 alink_mini
```

#### 🔌 Protium Emulator HW Validation (How to verify on the board):
* **Top Wrapper:** `alink_mini_top`
* **ForceNet (Inputs to force/deposit at runtime):**
  * `seed[31:0]` = deposit seed (e.g. `32'h1234_5678`)
  * `go` = pulse `0 -> 1 -> 0` to start the test
* **TriggerNet (Capture arming event):**
  * `done` rising edge
* **MonitorNet (Variables to probe/check):**
  * `done`, `err_cnt[7:0]`, `chk_sig[31:0]`, `scratch0[31:0]`, `scratch1[31:0]`, `wrcnt[15:0]`
* **PASS Criteria:**
  1. `done` asserts high.
  2. `err_cnt` is `8'd0` (no readback mismatches).
  3. `wrcnt` reads `16'd2` (two successful register write cycles).
  4. `scratch0` holds `32'h5A5A_A5A5`, `scratch1` holds `32'hC3C3_3C3C`.
  5. `chk_sig` matches the signature value seen in your simulator run.

---
---

## Part 4: Build System 2 (Full ALINK — Decoded Chiplets)
*This is the full chiplet configuration. We add address decoding to access either registers or memory banks, wraps them inside separate Master and Slave Chiplet modules, and runs the complete 3-phase automated command check FSM.*

### Step 1: Create a Folder
Create a folder here:
`D:\design_plans\pnp_ip\alink`

### Step 2: Copy Reusable Files
Copy the prerequisite leaf IPs and System 1 sub-modules you already built into this new folder:
- Copy `D:\design_plans\pnp_ip\lfsr_misr\lfsr32.sv` -> `D:\design_plans\pnp_ip\alink\lfsr32.sv`
- Copy `D:\design_plans\pnp_ip\lfsr_misr\misr32.sv` -> `D:\design_plans\pnp_ip\alink\misr32.sv`
- Copy `D:\design_plans\pnp_ip\alink_mini\axm_engine.sv` -> `D:\design_plans\pnp_ip\alink\axm_engine.sv`
- Copy `D:\design_plans\pnp_ip\alink_mini\axs_regs.sv` -> `D:\design_plans\pnp_ip\alink\axs_regs.sv`

### Step 3: Generate the Decoder, SRAM, and Checker
Use your local models to generate the remaining files needed for the complete ALINK spec:
1. **axs_dec.sv** (RTL, AL-06): Directs transactions to regs (addr[15]=0) or memory (addr[15]=1).
2. **axs_mem.sv** (RTL, AL-08): Connects the SRAM memory bank to the AXI channel.
3. **cmd_gen.sv** (RTL, AL-01): The full 3-phase automated test driver (uses `lfsr32` and `misr32`).
4. **axil_pmon.sv** (RTL, AL-03): AXI protocol checker.
5. **axm_chiplet.sv** (RTL, AL-05): Wraps `cmd_gen`, `axm_engine`, and `axil_pmon`.
6. **axs_chiplet.sv** (RTL, AL-10): Wraps `axs_dec`, `axs_regs`, and `axs_mem`.
7. **alink_top.sv** (RTL, AL-11): The overall design top wrapper connecting both chiplets.
8. **tb_alink.sv** (Testbench): The self-checking testbench to verify full chiplet execution.

*Prompt templates for these blocks are located in the [CONSOLIDATED_AI_PROMPTING_GUIDE.md](file:///d:/design_plans/CONSOLIDATED_AI_PROMPTING_GUIDE.md) in your workspace.*

### Step 4: Run Sim & HW Validation for System 2
Run the following commands in PowerShell:
```powershell
cd D:\design_plans\pnp_ip
powershell -ExecutionPolicy Bypass -File scripts\run_sim.ps1 alink
```
Check that the output prints:
`*** PASS: tb_alink, 0 errors ***`

#### 🔌 Protium Emulator HW Validation (How to verify on the board):
* **Top Wrapper:** `alink_top`
* **ForceNet (Inputs to force/deposit at runtime):**
  * `seed[31:0]` = deposit seed (e.g., `32'h1`)
  * `run` = pulse `0 -> 1 -> 0` to start the self-test
* **TriggerNet (Capture arming event):**
  * `test_done` rising edge (captures finish)
  * `pmon_err` rising edge (captures protocol violation)
* **MonitorNet (Variables to probe/check):**
  * `test_done`, `test_pass`, `err_cnt[7:0]`, `chk_sig[31:0]`, `led[7:0]`
* **PASS Criteria:**
  1. `test_pass` asserts to `1`, `err_cnt` remains `8'd0`, and `chk_sig` matches the C golden reference.
  2. Negative check: Runtime force `arready = 0` permanently on the slave side of the bus -> triggers FSM timeout -> `test_pass` drops to `0` and `pmon_err` rises (indicating `err_stall = 1`).
