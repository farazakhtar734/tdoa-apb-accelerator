# tdoa-apb-accelerator

Synthesizable fixed-point discrete cross-correlation accelerator interfaced via an ARM AMBA APB3 bus. Designed for real-time Time Difference of Arrival (TDOA) RF emitter localization, offloading sample correlation and peak-lag detection from the host CPU.

---

## Key Hardware Features

- **Core Datapath:** 2-stage pipelined Multiply-Accumulate (MAC) engine operating on signed 16-bit (Q1.15) samples.
- **Dynamic Range:** 40-bit accumulator providing 8 guard bits to prevent overflow over 256-sample summation windows without saturation.
- **Search Window:** Hardware finite state machine (FSM) evaluating 8 discrete lag hypotheses ($\tau \in [0, 7]$) across a 16-sample reference buffer and a 32-sample search buffer.
- **Automatic Peak Detection:** In-datapath digital comparator tracking maximum correlation score and optimal delay index $\tau$ without software intervention.
- **Bus Interface:** AMBA APB3 slave with zero-wait-state transfers (`PREADY = 1`), level-sensitive interrupt (`irq`), and Write-1-to-Clear (`W1C`) status handling.
- **Implementation Metrics:** 4,781 standard cells, 980 D-flip-flops, zero inferred latches.

---

## Architecture

```text
AMBA APB3 System Bus
      (PCLK, PRESETn, PADDR, PWDATA, PRDATA)
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ tdoa_apb_wrapper                                            │
│                                                             │
│ Registers:                                                  │
│ [0x00] CTRL     : START bit, IRQ enable                     │
│ [0x04] STATUS   : BUSY flag, W1C DONE flag                  │
│ [0x08] TAU      : Optimal lag index (4-bit)                 │
│ [0x0C] SCORE_L  : Peak score lower 32 bits                  │
│ [0x10] SCORE_H  : Peak score upper 8 bits (sign-extended)   │
│ [0x14] LOAD_X   : Packaged {addr[3:0], sample[15:0]}        │
│ [0x18] LOAD_Y   : Packaged {addr[4:0], sample[15:0]}        │
│                                                             │
│ Interrupt:                                                  │
│ irq = CTRL[1] & STATUS[1]                                   │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ tdoa_correlator                                             │
│                                                             │
│ Buffers:                                                    │
│ - RAM_X : 16 entries × 16-bit (Reference window)            │
│ - RAM_Y : 32 entries × 16-bit (Search window)               │
│                                                             │
│ FSM Controller:                                             │
│ IDLE ──► INIT_LAG ──► STREAM ──► DRAIN ──► PEAK_CHECK ──┐   │
│   ▲                                                     │   │
│   └─────────────────── FINISHED ◄───────────────────────┘   │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ tdoa_mac                                                    │
│                                                             │
│ Stage 1 : 16-bit × 16-bit signed multiplier ──► mul_reg     │
│ Stage 2 : 40-bit accumulator with sign extension            │
└─────────────────────────────────────────────────────────────┘
```

---

## Mathematical Formulation

The core computes the discrete cross-correlation sequence $R_{xy}[\tau]$:

$$R_{xy}[\tau] = \sum_{n=0}^{N-1} x[n] \cdot y[n + \tau], \quad \tau \in [0, \tau_{max}-1]$$

Where:
- $N = 16$ (reference sample window length)
- $\tau_{max} = 8$ (evaluated time-delay hypotheses)
- $x[n] \in [-1.0, +0.9999]$ (signed Q1.15 fixed-point)
- $y[n] \in [-1.0, +0.9999]$ (delayed received stream in search window)

The optimal time delay $\tau_{opt}$ is selected by hardware:

$$\tau_{opt} = \arg\max_{\tau} R_{xy}[\tau]$$

---

## Memory-Mapped Register Specification

Base Address: Configurable by SoC interconnect decoder (default 8-bit decode).

| Offset | Register Name | Access | Width | Description |
|:------:|:-------------:|:------:|:-----:|:------------|
| `0x00` | `REG_CTRL`    | R/W    | 2     | Bit [0]: Write `1` to initiate correlation (auto-clearing pulse).<br>Bit [1]: Hardware interrupt enable (`IRQ_EN`). |
| `0x04` | `REG_STATUS`  | Mixed  | 2     | Bit [0] (RO): `BUSY` indicator (core active).<br>Bit [1] (R/W1C): `DONE` flag. Asserted on completion. Write `1` to clear. |
| `0x08` | `REG_TAU`     | RO     | 4     | Detected lag index $\tau \in [0, 7]$ corresponding to maximum correlation peak. |
| `0x0C` | `REG_SCORE_L` | RO     | 32    | Bits [31:0] of the 40-bit signed maximum correlation score. |
| `0x10` | `REG_SCORE_H` | RO     | 8     | Bits [39:32] of the 40-bit signed maximum correlation score (sign-extended to bit 31 on reads). |
| `0x14` | `REG_LOAD_X`  | WO     | 20    | Bits [19:16]: Buffer X index (`0-15`).<br>Bits [15:0]: Signed 16-bit reference sample. |
| `0x18` | `REG_LOAD_Y`  | WO     | 21    | Bits [20:16]: Buffer Y index (`0-31`).<br>Bits [15:0]: Signed 16-bit search sample. |

---

## Synthesis Results (Yosys Open Synthesis Engine)

Target technology: Generic CMOS Standard Cell Library.

```text
=== Design Hierarchy Breakdown ===
tdoa_apb_wrapper
└── tdoa_correlator
    └── tdoa_mac

=== Cell Count Summary ===
Total cells: 4,781
Sequential cells (Flip-Flops): 980
- Sample storage (RAM_X + RAM_Y): 768 (DFFE_PP)
- Datapath pipeline registers: 74 (DFFE_PN0P, $DFF_PN0)
- Control logic & peak registers: 138
Inferred latches: 0 (Fully synchronous design)

=== Combinational Breakdown ===
AND gates: 1,379
Multiplexer cells ($MUX): 1,047
XOR gates: 719
OR gates: 560
Inverters / Buffers: 96
```

### Storage Register Analysis

The 768 storage flip-flops map directly to physical buffer bit demands:

- $\text{RAM\_X}: 16 \text{ words} \times 16 \text{ bits} = 256 \text{ registers}$
- $\text{RAM\_Y}: 32 \text{ words} \times 16 \text{ bits} = 512 \text{ registers}$
- $\text{Total buffer storage} = 256 + 512 = 768 \text{ bits}$

---

## Verification & Protocol Compliance

Verification is implemented in `tb/tb_tdoa_apb.sv` using an APB3 Bus Functional Model (BFM) with concurrent assertion monitoring.

### 1. Test Stimulus

- An asymmetric 16-sample pulse waveform is written to `RAM_X`.
- The identical pulse pattern is shifted by 3 sample intervals ($\tau_{inject} = 3$) and written to `RAM_Y` across indices `3` to `18`.
- The background of `RAM_Y` is zero-padded.

### 2. Verified Results

- **Peak Lag Detected:** $\tau = 3$ (Exact match)
- **Peak Score Computed:** `4,057,250,000`
- **Reference Model Score:** `4,057,250,000` (Zero arithmetic deviation)
- **Interrupt Servicing:** `irq` pin asserted high on core completion and successfully cleared to `0` following a Write-1-to-Clear transaction to `REG_STATUS[1]`.

### 3. Active Protocol Assertions

- `APB_SETUP_TO_ACCESS`: Validates standard phase transition (`psel && !penable` $\implies$ next cycle `penable`).
- `ADDR_STABILITY`: Guarantees address and control signals do not drift during wait states.
- `IRQ_INVARIANT`: Verifies `irq` cannot assert unless `IRQ_EN` is configured and calculation is verified complete.
- `BOUNDS_CHECK`: Verifies calculated lag remains within valid architectural bounds ($0 \le \tau \le 7$).

---

## Directory Structure

```text
tdoa_accelerator/
├── rtl/
│   ├── tdoa_mac.sv          # 2-stage pipelined Q1.15 signed MAC unit
│   ├── tdoa_correlator.sv   # Buffer storage, lag sweeper FSM, peak detector
│   └── tdoa_apb_wrapper.sv  # APB3 bus interface, register map, W1C logic
├── tb/
│   ├── tb_tdoa_mac.sv       # Unit testbench for isolated MAC pipeline
│   ├── tb_tdoa_correlator.sv# Unit testbench for correlation engine
│   └── tb_tdoa_apb.sv       # Top-level APB3 SoC integration testbench
├── syn/
│   ├── synth.ys             # Yosys synthesis execution script
│   └── synth.log            # Area and gate-level cell breakdown report
├── sta/
│   ├── timing.sdc           # Clock definition and I/O delay constraints
│   └── run_sta.tcl          # OpenSTA timing analysis script
├── sim/                     # Compiled simulation binaries and VCD dumps
└── docs/                    # Register definitions and architectural diagrams
```

---

## How to Build and Simulate

### Prerequisites

- Icarus Verilog (`iverilog` v11+)
- Yosys (`yosys` 0.30+)
- GTKWave

### 1. Run Top-Level APB Simulation

```bash
cd ~/asic_ws/tdoa_accelerator
iverilog -g2012 -o sim/tdoa_apb_sim \
    rtl/tdoa_mac.sv \
    rtl/tdoa_correlator.sv \
    rtl/tdoa_apb_wrapper.sv \
    tb/tb_tdoa_apb.sv
vvp sim/tdoa_apb_sim
```

### 2. Inspect Waveforms

```bash
gtkwave sim/tdoa_apb.vcd &
```

### 3. Run Synthesis

```bash
yosys syn/synth.ys | tee syn/synth.log
```

---

## Engineering Trade-Offs & Silicon Decisions

### Pipelined vs. Single-Cycle MAC

A single-cycle $16 \times 16$ multiply-accumulate path creates a long combinational chain ($t_{mult\_16} + t_{add\_40}$). Splitting the operation across two cycles via `mul_reg` balances stage delays, enabling higher synthesis frequencies ($f_{max}$).

### W1C vs. Read-Clear Status

Auto-clearing interrupt status on register read introduces silent race conditions if a second event occurs simultaneously with the bus read. An explicit Write-1-to-Clear mechanism guarantees deterministic handshake between the interrupt service routine (ISR) and peripheral hardware.

### Dedicated Register Buffers vs. Shared Single-Port SRAM

The reference and search windows are instantiated as distributed register arrays rather than unified SRAM. This enables concurrent multi-port access during the STREAM phase, loading $x[n]$ and $y[n+\tau]$ simultaneously every clock cycle without memory arbitration stalls.
