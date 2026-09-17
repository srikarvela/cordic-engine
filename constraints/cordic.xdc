# OOC clock constraint for cordic_top. The 3.000 ns target is deliberately
# tighter than the 250 MHz used by the sibling repos: Fmax is reported as
# 1 / (period - WNS), which is only meaningful when the tools are pushed close
# to what the fabric can do. tcl/cordic_synth.tcl reads the period back from the
# clock object, so this is the only place it is written.
create_clock -name clk -period 3.000 [get_ports clk]

# Standard OOC boundary constraints: block I/O arrives/departs near the clock
# edge. Every input and output of cordic_top is registered, so these only
# cover the port-to-first-flop and last-flop-to-port hops.
set_input_delay  -clock clk 0.300 [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_output_delay -clock clk 0.300 [all_outputs]
