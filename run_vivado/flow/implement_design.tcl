cd [file normalize [file join [file dirname [info script]] ..]]

# Run implementation and emit reports.
open_project project/thinpad_top.xpr

set synth_run [get_runs synth_1]
reset_run $synth_run
launch_runs synth_1
wait_on_run synth_1

set synth_progress [get_property PROGRESS $synth_run]
set synth_status [get_property STATUS $synth_run]
puts "synth_1 progress: $synth_progress"
puts "synth_1 status: $synth_status"

if {$synth_progress ne "100%"} {
    puts "ERROR: Synthesis did not complete."
    close_project
    exit 1
}

if {[string first "ERROR" $synth_status] >= 0 || [string first "Failed" $synth_status] >= 0} {
    puts "ERROR: Synthesis failed: $synth_status"
    close_project
    exit 1
}

set impl_run [get_runs impl_1]
reset_run $impl_run

launch_runs impl_1
wait_on_run impl_1

set impl_progress [get_property PROGRESS $impl_run]
set impl_status [get_property STATUS $impl_run]
puts "impl_1 progress: $impl_progress"
puts "impl_1 status: $impl_status"

if {$impl_progress ne "100%"} {
    puts "ERROR: Implementation did not complete."
    close_project
    exit 1
}

if {[string first "ERROR" $impl_status] >= 0} {
    puts "ERROR: Implementation failed: $impl_status"
    close_project
    exit 1
}

if {[string first "Failed Timing" $impl_status] >= 0} {
    puts "WARNING: Implementation completed with timing violations. Reports will be generated before timing check fails the job."
} elseif {[string first "Failed" $impl_status] >= 0} {
    puts "ERROR: Implementation failed: $impl_status"
    close_project
    exit 1
}

open_run impl_1
report_utilization -file project/thinpad_top.runs/impl_1/utilization.rpt -pb project/thinpad_top.runs/impl_1/utilization.pb
report_timing_summary -delay_type min_max -report_unconstrained \
    -file project/thinpad_top.runs/impl_1/timing_summary.rpt

close_project
exit 0
