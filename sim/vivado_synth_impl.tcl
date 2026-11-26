set part xc7z020clg400-1
create_project -in_memory -part $part
read_verilog -sv [list rtl/mac_unit.sv rtl/matmul_core.sv rtl/matmul_axil.sv]
read_xdc constraints/matmul.xdc
synth_design -top matmul_axil -part $part -mode out_of_context
report_utilization    -file reports_synth_util.rpt
report_timing_summary -file reports_synth_timing.rpt
opt_design
place_design
route_design
report_utilization    -file reports_impl_util.rpt
report_timing_summary -file reports_impl_timing.rpt
report_power          -file reports_impl_power.rpt
