create_clock -name aclk -period 10.0 [get_ports s_axi_aclk]
set_clock_uncertainty 0.2 [get_clocks aclk]
set_clock_transition  0.1 [get_clocks aclk]

set in_ports  [remove_from_collection [all_inputs] [get_ports s_axi_aclk]]
set_input_delay  -clock aclk -max 4.0 $in_ports
set_input_delay  -clock aclk -min 0.5 $in_ports
set_output_delay -clock aclk -max 4.0 [all_outputs]
set_output_delay -clock aclk -min 0.0 [all_outputs]

set_load 0.05 [all_outputs]
