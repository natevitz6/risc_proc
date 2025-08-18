# --- Only RV32GCV target ---
export TARGET=rv32gv

# --- Toolchain paths ---
RISCV32GCV := /home/natevitz/opt/riscv32gcv
VERILATOR := /home/natevitz/verilator/bin/verilator

# --- Phony targets ---
.PHONY: all clean test result-verilator libmc dumphex
all: test result-verilator
# --- Toolchain setup ---
RISCV_PREFIX = $(RISCV32GCV)/bin/riscv32-unknown-elf
RISCV_LIB    = $(RISCV32GCV)/lib/gcc/riscv32-unknown-elf/15.1.0
MARCH        = rv32gv
MABI         = ilp32

# --- Compiler/assembler/linker ---
CC = $(RISCV_PREFIX)-gcc
AS = $(RISCV_PREFIX)-as
LD = $(RISCV_PREFIX)-ld

SSFLAGS     = -march=$(MARCH) -mabi=$(MABI)
CCFLAGS     = -march=$(MARCH) -mabi=$(MABI) -std=gnu11 -Wno-builtin-declaration-mismatch -Ilibmc
LDFLAGS     = -T ld.script -nostartfiles
LDPOSTFLAGS = -Llibmc -lmc -L$(RISCV_LIB) -lgcc

TOOLS  = dumphex
LIBS   = libmc/libmc.a
TEST_S = start.s
TEST_C = test.c

.c.o:
	$(CC) $(CCFLAGS) -c $*.c

.s.o:
	$(AS) $(SSFLAGS) -c $*.s -o $*.o

libmc/libmc.a:
	cd libmc && make clean && make

dumphex: dumphex.c
	gcc -o dumphex dumphex.c

test: $(TEST_S:.s=.o) $(TEST_C:.c=.o) $(LIBS) $(TOOLS)
	$(CC) $(LDFLAGS) -march=$(MARCH) -mabi=$(MABI) -Wl,-m,elf32lriscv -o test \
		$(TEST_S:.s=.o) $(TEST_C:.c=.o) $(LDPOSTFLAGS) \
		-L$(dir $(shell $(CC) -print-libgcc-file-name)) -lgcc
	RISCV_PREFIX=$(RISCV_PREFIX) /bin/bash ./elftohex.sh test .
	$(RISCV_PREFIX)-objdump -d test > test.dump

result-verilator: top.sv verilator_top.cpp pipe_core.sv test
	$(VERILATOR) -O0 --cc --build --top-module top top.sv verilator_top.cpp --exe
	cp obj_dir/Vtop ./result-verilator
	rm -rf obj_dir
	./result-verilator

clean:
	rm -rf dumphex test.vcd obj_dir/ *.o result-verilator *.hex test.bin test