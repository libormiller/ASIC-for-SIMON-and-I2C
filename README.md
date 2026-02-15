# Simon Cipher Core with I2C Interface

This repository contains a hardware implementation of the **Simon block cipher** (32/64 configuration) integrated with an **I2C Slave interface**. The design allows a Master device to write a 64-bit key and 32-bit plaintext over I2C, trigger the encryption process, and read back the resulting ciphertext.

##  Architecture Overview

The system is organized into three distinct layers:
1.  **I2C Slave Layer (`i2c_slave.v`):** A robust I2C slave implementation that translates serial bus transactions into AXI-Stream data transfers.
2.  **Top-Level Wrapper (`simon_top.v`):** Manages the internal register bank, handles the I2C-to-Register mapping, and controls the encryption flow.
3.  **Cryptographic Core (`simon_rounds.v`):** The dedicated hardware engine that performs the Simon cipher rounds.

---

##  I2C Specifications

* **Device Address:** `0x50` (7-bit).
* **Physical Interface:** Uses standard `sda_pin` and `scl_pin` with tri-state logic.
* **Addressing Logic:** The first byte of an I2C write transaction is treated as the **Register Address Pointer**. Subsequent bytes are written to that address and following addresses via **auto-increment**.

---

##  Register Map

The internal registers are 8-bit wide and mapped as follows:

| Address (Hex) | Name | Description | Access |
| :--- | :--- | :--- | :--- |
| **0x00 - 0x07** | `key_reg` | 64-bit encryption key (LSB first). | Write |
| **0x08 - 0x0B** | `block_reg` | 32-bit plaintext block (LSB first). | Write |
| **0x0C** | `control` | Bit [0]: Start encryption (Pulse). | Write |
| **0x10 - 0x13** | `cipher_reg`| 32-bit resulting ciphertext (LSB first). | Read |
| **0x14** | `status` | Bit [1]: Done, Bit [0]: Busy. | Read |

---

##  Communication Protocol

### Writing to the Core
To perform encryption:
1.  Send **START** condition and **Slave Address** (`0xA0` for Write).
2.  Send **Register Address** `0x00`.
3.  Stream 8 bytes of the **Key** and 4 bytes of **Plaintext** (auto-increment handles the addresses).
4.  Send **STOP**.
5.  Send **START** + **Slave Address** + **Register Address** `0x0C` + **Data** `0x01` to start the core.

### Reading the Result
1.  Send **START** + **Slave Address** (`0xA0`) + **Register Address** `0x10`.
2.  Send **REPEATED START** + **Slave Address** (`0xA1` for Read).
3.  Read 4 bytes of **Ciphertext**.
4.  Send **STOP**.

---

## Simulation & Verification

The project is verified using **Cocotb** and **Icarus Verilog**.

### Delta Cycle Loop Prevention
Because Icarus Verilog can struggle with `inout` port simulation (causing "stuck" simulations), the testbench uses **shadow registers** for the Master drivers. 
* **Master SDA/SCL Enable:** Controlled by Python to pull the bus to ground or release it.
* **Wired-AND Logic:** The final pin state is resolved in `simon_top.v` based on both Master and Slave drivers to avoid simulator feedback loops.

### Running Tests
Ensure you have `cocotb` and `iverilog` installed, then run:
```bash
make