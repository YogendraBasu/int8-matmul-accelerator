SRC     := rtl/mac_unit.sv rtl/matmul_core.sv rtl/matmul_axil.sv
TB      := tb/tb_matmul_axil.sv
TOP     := tb_matmul_axil
NUM_MAC ?= 4
CC      ?= gcc
CFLAGS  := -std=c99 -Wall -Wextra -Werror -O2 -Isw

.PHONY: all sim lint model driver clean

all: model driver sim

sim:
	verilator --binary --timing --assert --trace -Wno-fatal -GNUM_MAC=$(NUM_MAC) --top-module $(TOP) $(SRC) $(TB)
	./obj_dir/V$(TOP)

lint:
	verilator --lint-only -Wall -Wno-fatal --top-module matmul_axil $(SRC)

model:
	python3 scripts/golden_model.py
	python3 -m unittest discover -s scripts -v

driver: sw/test_driver
	./sw/test_driver

sw/test_driver: sw/test_driver.c sw/matmul_driver.c sw/matmul_driver.h sw/matmul_regs.h
	$(CC) $(CFLAGS) -o $@ sw/test_driver.c sw/matmul_driver.c

clean:
	rm -rf obj_dir dump.vcd sw/test_driver vectors work xsim.dir
