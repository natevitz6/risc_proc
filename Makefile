
include site-config.sh
goal: result-verilator
CC=$(RISCV_PREFIX)-gcc
AS=$(RISCV_PREFIX)-as
LD=$(RISCV_PREFIX)-ld

SSFLAGS=-march=rv32i -mabi=ilp32
CCFLAGS=-march=rv32i -mabi=ilp32 -std=gnu11 -Wno-builtin-declaration-mismatch -Ilibmc
LDFLAGS=-T ld.script -nostartfiles
LDPOSTFLAGS= -Llibmc -lmc -L$(RISCV_LIB) -lgcc
TOOLS=dumphex
LIBS=libmc/libmc.a

TEST_S=start.s
TEST_C=test.c

.c.o:
	$(CC) $(CCFLAGS) -c $*.c

.s.o:
	$(AS) $(SSFLAGS) -c $*.s -o $*.o


libmc/libmc.a:
	cd libmc; make clean; make; cd ..

dumphex: dumphex.c
	gcc -o dumphex dumphex.c

test: $(TEST_S:.s=.o) $(TEST_C:.c=.o) $(LIBS) $(TOOLS)
	$(CC) $(LDFLAGS) -march=rv32i -mabi=ilp32 -Wl,-m,elf32lriscv -o test \
		$(TEST_S:.s=.o) $(TEST_C:.c=.o) $(LDPOSTFLAGS) \
		-L$(dir $(shell $(CC) -print-libgcc-file-name)) -lgcc
	/bin/bash ./elftohex.sh test .

result-verilator: top.sv verilator_top.cpp pipe_core.sv test
	 $(VERILATOR) -O0 --cc --build --top-module top top.sv verilator_top.cpp --exe
	 cp obj_dir/Vtop ./result-verilator
	 rm -rf obj_dir
	 ./result-verilator

clean:
	rm -rf dumphex test.vcd obj_dir/ *.o result-verilator *.hex test.bin test

