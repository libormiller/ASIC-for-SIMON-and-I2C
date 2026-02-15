# Simon 32/64 Cipher Core with I2C Interface

This repository contains a hardware implementation of the **Simon block cipher** (32/64 configuration) integrated with an **I2C Slave interface**. The design allows a Master device to write a 64-bit key and 32-bit data block, configure the operation mode (Encrypt/Decrypt), and read back the result.

## Architecture Overview

The system is organized into three distinct layers:
1.  **I2C Slave Layer (`i2c_slave.v`):** A robust I2C slave implementation that translates serial bus transactions into AXI-Stream data transfers.
2.  **Top-Level Wrapper (`simon_top.v`):** Manages the internal register bank, handles the I2C-to-Register mapping, and controls the Simon Core state machine.
3.  **Cryptographic Core (`simon_rounds.v`):** The dedicated hardware engine that performs the Simon cipher rounds (32 rounds).

---

## I2C Specifications

* **Device Address:** `0x50` (7-bit).
* **Physical Interface:** Uses standard `sda_pin` and `scl_pin` with tri-state logic (Open-Drain).
* **Addressing Logic:** The first byte of an I2C write transaction is treated as the **Register Address Pointer**. Subsequent bytes are written to that address and following addresses via **auto-increment**.

---

## Register Map

All registers are 8-bit wide. Multi-byte registers are stored **Little-Endian** (LSB at lower address).

| Address (Hex) | Name | Access | Description |
| :--- | :--- | :--- | :--- |
| **0x00 - 0x07** | `KEY` | R/W | 64-bit Key (LSB first: `0x00` is Key[7:0]). |
| **0x08 - 0x0B** | `DATA_IN` | R/W | 32-bit Input Block (Plaintext or Ciphertext). LSB first. |
| **0x0C** | `CONTROL` | R/W | **Bit [0]: CORE_RST** (1 = Reset/Load, 0 = Run)<br>**Bit [1]: CORE_MODE** (0 = Encrypt, 1 = Decrypt) |
| **0x10 - 0x13** | `RESULT` | R | 32-bit Output Block (Ciphertext or Plaintext). Valid only when `DONE` is 1. |
| **0x14** | `STATUS` | R | **Bit [1]: DONE** (1 = Valid Result Ready)<br>**Bit [0]: BUSY** (1 = Calculating) |

---

## Communication Protocol

### 1. Writing Key & Data
To prepare for an operation, write the Key and Input Data.
1.  Send **START** condition + **Slave Address** (Write).
2.  Send **Register Address** `0x00`.
3.  Write 8 bytes of **Key** and 4 bytes of **Data** (Address auto-increments from `0x00` to `0x0B`).
4.  Send **STOP**.

### 2. Execution (Load & Run)
The core uses a latch-based start mechanism. You must first assert Reset to load data, then de-assert it to run. The Mode bit must be stable during both steps.

**For Encryption:**
1.  Write `0x0C` with data `0x01` (Rst=1, Mode=Enc). -> *Loads data.*
2.  Write `0x0C` with data `0x00` (Rst=0, Mode=Enc). -> *Starts calculation.*

**For Decryption:**
1.  Write `0x0C` with data `0x03` (Rst=1, Mode=Dec). -> *Loads data & pre-computes keys.*
2.  Write `0x0C` with data `0x02` (Rst=0, Mode=Dec). -> *Starts calculation.*

### 3. Reading the Result
1.  (Optional) Poll Register `0x14` until Bit 1 is `1`.
2.  Send **START** + **Slave Address** (Write) + **Register Address** `0x10`.
3.  Send **REPEATED START** + **Slave Address** (Read).
4.  Read 4 bytes of **Result**.
5.  Send **STOP**.

---

## ASIC Implementation Notes

This design is "Tape-out Ready" from a logic perspective, but requires specific handling for synthesis:

1.  **I/O Pads:** The Verilog code uses `tri1` for simulation. For synthesis, `sda_pin` and `scl_pin` must be connected to technology-specific **Bidirectional Open-Drain I/O Cells**.
2.  **Glitch Filter:** The `i2c_slave` instance is configured with `.FILTER_LEN(1)`. For high-speed system clocks (>50 MHz) or noisy environments, increase this value to filter pulses shorter than 50ns.
3.  **Reset:** Ensure a proper **Power-On Reset (POR)** circuit drives the global `rst` signal.

## Simulation

The project is verified using **Cocotb** (Python) and **Icarus Verilog**.

```bash
# Install dependencies
pip install cocotb cocotbext-i2c

# Run tests
make