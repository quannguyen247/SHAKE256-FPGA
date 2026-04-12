open_project C:/Users/Quan/Desktop/SHAKE256/Implementation/SHAKE256.xpr
open_run impl_1
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
write_bitstream -force C:/Users/Quan/Desktop/SHAKE256/Implementation/SHAKE256.runs/impl_1/shake256_fpga_top.bit
close_project
exit
