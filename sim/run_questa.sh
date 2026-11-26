#!/bin/sh
MAC=${1:-4}
vlib work
vlog -sv +cover=bcesf rtl/mac_unit.sv rtl/matmul_core.sv rtl/matmul_axil.sv tb/tb_matmul_axil.sv +define+USE_COVERGROUP
vsim -c -coverage -GNUM_MAC=$MAC tb_matmul_axil -do "run -all; coverage report -summary; coverage save sim.ucdb; quit"
