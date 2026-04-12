set proj_path [file normalize [file join [file dirname [info script]] .. SHAKE256.xpr]]
puts "OPEN_PROJECT=$proj_path"
open_project $proj_path

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

reset_run synth_1
reset_run impl_1

launch_runs synth_1 -jobs 8
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "SYNTH_STATUS=$synth_status"

if {[string match "*ERROR*" $synth_status]} {
  close_project
  exit 1
}

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "IMPL_STATUS=$impl_status"

set bit_files [glob -nocomplain [file normalize [file join [file dirname $proj_path] SHAKE256.runs impl_1 *.bit]]]
if {[llength $bit_files] > 0} {
  puts "BIT_PATH=[lindex $bit_files 0]"
}

close_project
if {[string match "*ERROR*" $impl_status]} {
  exit 2
}
exit 0
