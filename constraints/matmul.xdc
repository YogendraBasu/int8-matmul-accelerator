create_clock -name aclk -period 10.000 [get_ports s_axi_aclk]
set_property CFGBVS VCCO [current_design]
