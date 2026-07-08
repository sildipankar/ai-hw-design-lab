# =============================================================================
# synth.tcl -- ONE reusable non-project batch synthesis script for all blocks.
#
# Usage:
#   vivado -mode batch -source scripts\synth.tcl -tclargs <block_dir> <top> [part]
#
# - globs every *.sv in <block_dir>, excludes tb_*.sv (sim-only by convention)
# - out-of-context synth: no pins/constraints needed, checks constructs only
# - default part is a small Artix-7; synthesizability of constructs does not
#   depend on the part. Falls back to any installed part if not present.
# =============================================================================
set block_dir [lindex $argv 0]
set top       [lindex $argv 1]
set part      "xc7a35ticsg324-1L"
if {[llength $argv] >= 3} { set part [lindex $argv 2] }

if {[llength [get_parts -quiet $part]] == 0} {
    set part [lindex [get_parts] 0]
    puts "WARNING: requested part not installed, falling back to: $part"
}

set rtl {}
foreach f [glob -nocomplain [file join $block_dir *.sv]] {
    if {![string match "tb_*" [file tail $f]]} { lappend rtl $f }
}
if {[llength $rtl] == 0} { puts "ERROR: no RTL files in $block_dir"; exit 1 }

puts "INFO: part=$part top=$top files=$rtl"
read_verilog -sv $rtl
synth_design -top $top -part $part -mode out_of_context
report_utilization    -file ${top}_utilization.rpt
report_timing_summary -file ${top}_timing.rpt
puts "SYNTH_OK $top"
exit 0
