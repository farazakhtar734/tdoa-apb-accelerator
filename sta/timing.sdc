create_clock -name pclk -period 10.0 [get_ports pclk]
set_input_delay -clock pclk 2.0 [get_ports {paddr[*] psel penable pwrite pwdata[*]}]
set_output_delay -clock pclk 2.0 [get_ports {prdata[*] pready pslverr irq}]
