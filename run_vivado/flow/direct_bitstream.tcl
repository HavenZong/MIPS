cd [file normalize [file join [file dirname [info script]] ..]]

open_project project/thinpad_top.xpr
file mkdir project/thinpad_top.runs/impl_1

synth_design -top thinpad_top -part xc7a200tfbg676-2
opt_design -directive RuntimeOptimized
place_design
phys_opt_design
route_design -directive Explore
phys_opt_design -directive AggressiveExplore
route_design -directive Explore

report_utilization -file project/thinpad_top.runs/impl_1/utilization.rpt \
    -pb project/thinpad_top.runs/impl_1/utilization.pb
report_timing_summary -delay_type min_max -report_unconstrained \
    -file project/thinpad_top.runs/impl_1/timing_summary.rpt

write_bitstream -force project/thinpad_top.runs/impl_1/thinpad_top.bit

close_project
exit 0
