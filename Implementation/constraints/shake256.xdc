create_clock -period 5.000 -name sys_clk [get_ports clk]

set_switching_activity -default_toggle_rate 50.000
set_switching_activity -toggle_rate 50.000 -type {lut} -static_probability 0.500 -all 
set_switching_activity -toggle_rate 50.000 -type {register} -static_probability 0.500 -all 
set_switching_activity -toggle_rate 50.000 -type {shift_register} -static_probability 0.500 -all 
set_switching_activity -toggle_rate 50.000 -type {lut_ram} -static_probability 0.500 -all 
set_switching_activity -toggle_rate 50.000 -type {io_output} -static_probability 0.500 -all 