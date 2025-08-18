# CSE470: Pipelined RISC-V Core with Vector ISA and Cache Prefetcher

## Project Overview

This project implements a pipelined RISC-V processor core supporting the RV32GCV instruction set architecture, which includes both standard integer instructions and RISC-V vector extensions. The design is written in SystemVerilog and targets educational and research use for understanding modern processor architecture concepts such as pipelining, hazard management, vector processing, and cache prefetching.

## Features

- **Five-stage Pipeline:**  
  The core implements a classic five-stage pipeline: Instruction Fetch (IF), Instruction Decode (ID), Execute (EX), Memory Access (MEM), and Write Back (WB). Pipeline registers and hazard detection logic ensure correct instruction flow and data forwarding.

- **RISC-V RV32GCV ISA Support:**  
  The processor supports the RV32GCV ISA, enabling both scalar and vector instructions. Vector instructions are detected in the decode stage and dispatched to a dedicated vector unit for parallel computation.

- **Vector Unit:**  
  The vector unit handles vector arithmetic, logical operations, and memory accesses. It interfaces with the core to receive instructions and operands, and returns results upon completion. The design includes logic to stall the pipeline while vector operations are in progress, ensuring correct synchronization.

- **Hazard Detection and Forwarding:**  
  The core includes logic for detecting and resolving data hazards, including forwarding paths for scalar and vector instructions. Pipeline stalls are inserted when necessary to maintain correctness.

- **Cache and Prefetcher:**  
  The memory subsystem includes a cache with prefetching capability. The cache prefetcher predicts future memory accesses and loads data into the cache ahead of time, reducing memory latency and improving overall performance.

- **Memory System:**  
  The memory module supports both scalar and vector accesses, allowing for instruction fetches, scalar loads/stores, and vector loads/stores. It is designed to work seamlessly with the cache and vector unit.

- **Extensive Debugging Output:**  
  The processor and vector unit include detailed display statements for cycle-by-cycle debugging. These outputs show pipeline register contents, memory requests and responses, vector register file states, and instruction execution details, aiding in development and verification.

## File Structure

- `pipe_core.sv` — Main pipelined processor core, including pipeline registers, hazard logic, and instruction decode.
- `riscv32_vector.sv` — Vector unit implementation for RVV instructions.
- `memory.sv` — Memory module supporting scalar and vector accesses.
- `memory_io.sv` — Memory interface logic.
- `libmc/` — Microcontroller support library.
- `Makefile` — Build system for compiling and running the processor and tests.
- `start.s` — Assembly test program demonstrating vector operations.
- `test.c` — C test program for additional functionality.
- `README.md` — Project documentation.

## How to Build and Run

1. **Set up the RISC-V toolchain:**  
   Ensure the RV32GCV toolchain is installed and paths are set in `site-config.sh`.

2. **Build the project:**  
   Run `make` in the project root to compile all sources, assemble the test programs, and generate the ELF and HEX files.

3. **Run simulation:**  
   Use the provided Verilator targets to simulate the processor and observe the debug output.

4. **View disassembly:**  
   After building, inspect `test.dump` for the disassembled instructions.


