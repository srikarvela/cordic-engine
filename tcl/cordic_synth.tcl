# =============================================================================
# cordic_synth.tcl -- out-of-context synthesis + place & route of cordic_top,
#                     swept over N_ITER
#
#   vivado -mode batch -source tcl/cordic_synth.tcl -tclargs <W> <N_ITER> [<N_ITER> ...]
#   vivado -mode batch -source tcl/cordic_synth.tcl -tclargs 17 15          (make synth)
#   vivado -mode batch -source tcl/cordic_synth.tcl -tclargs 17 8 12 16 20  (make sweep)
#   ... -tclargs period:4.000 17 15    override the XDC clock period (timing-closure run)
#
# Non-project flow, no board or pin bring-up: each configuration is
# synthesized, placed and routed on its own with a clock constraint, so the
# numbers are real post-route timing/utilization, not synth-only estimates.
#
# Outputs (committed)
#   reports/N<N>_W<W>/utilization.rpt, timing_summary.rpt
#   reports/ppa.csv + docs/ppa_table.md are then built from those reports by
#   scripts/ppa_table.py (report_utilization "Slice LUTs" etc.), so the console
#   cell counts printed below are a progress indicator only.
# =============================================================================

set part       "xc7z020clg400-1" ;# Zynq-7020 / PYNQ-Z2, same part as the sibling repos

set period_override ""
if {[string match "period:*" [lindex $argv 0]]} {
    set period_override [string range [lindex $argv 0] 7 end]
    set argv [lrange $argv 1 end]
}
if {[llength $argv] < 2} {
    puts "usage: -tclargs <W> <N_ITER> \[<N_ITER> ...\]"
    exit 2
}
set W      [lindex $argv 0]
set n_list [lrange $argv 1 end]

set here [file normalize [file dirname [info script]]]
set root [file normalize [file join $here ..]]
set rdir [file join $root reports]
file mkdir $rdir

proc count_cells {pattern} {
    return [llength [get_cells -quiet -hierarchical -filter "IS_PRIMITIVE && REF_NAME =~ $pattern"]]
}

foreach n $n_list {
    puts "=== cordic_top OOC: N_ITER=$n W=$W part=$part ==="
    set out [file join $rdir "N${n}_W${W}[expr {$period_override eq "" ? "" : "_${period_override}ns"}]"]
    file mkdir $out

    create_project -in_memory -part $part
    foreach f [lsort [glob -directory [file join $root rtl] *.sv]] { read_verilog -sv $f }
    read_xdc -mode out_of_context [file join $root constraints cordic.xdc]

    synth_design -top cordic_top -part $part -mode out_of_context \
        -include_dirs [file join $root rtl] -generic N_ITER=$n -generic W=$W
    if {$period_override ne ""} { create_clock -name clk -period $period_override [get_ports clk] }
    opt_design
    place_design
    phys_opt_design
    route_design

    report_timing_summary -file [file join $out timing_summary.rpt]
    report_utilization    -file [file join $out utilization.rpt]

    set clk_period [get_property PERIOD [get_clocks clk]]
    set wns  [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
    set whs  [get_property SLACK [get_timing_paths -max_paths 1 -hold]]
    set fmax [format %.1f [expr {1000.0 / ($clk_period - $wns)}]]
    set lut  [count_cells LUT*]
    set srl  [count_cells SRL*]
    set ff   [count_cells FD*]
    set cy   [count_cells CARRY4]
    set dsp  [count_cells DSP48*]
    set bram [count_cells RAMB*]
    puts "=== N_ITER=$n W=$W: LUT cells=$lut SRL=$srl FF=$ff CARRY4=$cy DSP=$dsp WNS=$wns WHS=$whs Fmax=${fmax}MHz (primitive counts; Slice LUTs are in utilization.rpt) ==="

    close_project
}

puts "=== reports written under $rdir; run scripts/ppa_table.py to rebuild ppa.csv ==="
