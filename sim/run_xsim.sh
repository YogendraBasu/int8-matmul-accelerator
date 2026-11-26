#!/bin/sh
MAC=${1:-4}
xvlog -sv rtl/mac_unit.sv rtl/matmul_core.sv rtl/matmul_axil.sv tb/tb_matmul_axil.sv
xelab tb_matmul_axil -s tb_sim -debug typical -generic_top NUM_MAC=$MAC
xsim tb_sim -runall
