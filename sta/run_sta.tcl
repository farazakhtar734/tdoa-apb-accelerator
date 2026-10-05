read_verilog syn/tdoa_apb_netlist.v
link_design tdoa_apb_wrapper
read_sdc sta/timing.sdc
report_checks -path_delay max -fields {slew cap input nets fanout} -digits 3
report_worst_slack -max
