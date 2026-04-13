# SHAKE256 FPGA wrapper constraints (XDC command subset compatible)

# 250 MHz system clock target
create_clock -name sys_clk -period 5.000 [get_ports clk]

# Active-low asynchronous reset does not need timing closure.
set_false_path -from [get_ports rst_n]

# Generic I/O electrical standard. Replace with board-specific constraints as needed.
set_property IOSTANDARD LVCMOS33 [get_ports *]

# Temporary bitstream-unblock settings when board pin LOCs are not finalized yet.
# Remove these lines after adding PACKAGE_PIN constraints for all top-level ports.
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]

# Board pin template (fill with real package pins, then remove the UCIO/NSTD overrides above):
# set_property PACKAGE_PIN <PIN> [get_ports clk]
# set_property PACKAGE_PIN <PIN> [get_ports rst_n]
# set_property PACKAGE_PIN <PIN> [get_ports start_btn]
# set_property PACKAGE_PIN <PIN> [get_ports done_led]
# set_property PACKAGE_PIN <PIN> [get_ports {msg_byte[0]}]
# set_property PACKAGE_PIN <PIN> [get_ports {msg_byte[1]}]
# set_property PACKAGE_PIN <PIN> [get_ports {msg_byte[2]}]
# set_property PACKAGE_PIN <PIN> [get_ports {msg_byte[3]}]
# set_property PACKAGE_PIN <PIN> [get_ports {msg_byte[4]}]
# set_property PACKAGE_PIN <PIN> [get_ports {msg_byte[5]}]
# set_property PACKAGE_PIN <PIN> [get_ports {msg_byte[6]}]
# set_property PACKAGE_PIN <PIN> [get_ports {msg_byte[7]}]
# set_property PACKAGE_PIN <PIN> [get_ports {hash_byte[0]}]
# set_property PACKAGE_PIN <PIN> [get_ports {hash_byte[1]}]
# set_property PACKAGE_PIN <PIN> [get_ports {hash_byte[2]}]
# set_property PACKAGE_PIN <PIN> [get_ports {hash_byte[3]}]
# set_property PACKAGE_PIN <PIN> [get_ports {hash_byte[4]}]
# set_property PACKAGE_PIN <PIN> [get_ports {hash_byte[5]}]
# set_property PACKAGE_PIN <PIN> [get_ports {hash_byte[6]}]
# set_property PACKAGE_PIN <PIN> [get_ports {hash_byte[7]}]
