# Richard James Howe
# TCL Script for GTKWave on tb.ghw
#

set bits 15

gtkwave::/Edit/Set_Trace_Max_Hier 0
gtkwave::/Time/Zoom/Zoom_Amount -27.0
gtkwave::/View/Show_Filled_High_Values 1
gtkwave::setFromEntry 170ns

# top.tb.uut.cpu.c.first
set names {
	top.tb.rst
	top.tb.clk
	top.tb.uut.cpu.last
	top.tb.uut.cpu.c.state
	top.tb.uut.cpu.c.pc[15:0]
	top.tb.uut.cpu.cmd
	top.tb.uut.cpu.c.op[15:0]
	top.tb.uut.cpu.c.acc[15:0]
	top.tb.uut.cpu.ae
	top.tb.uut.cpu.ie
	top.tb.uut.cpu.oe
}

gtkwave::addSignalsFromList $names

foreach v $names {
	set a [split $v .]
	set a [lindex $a end]
	gtkwave::highlightSignalsFromList $v
	gtkwave::/Edit/Alias_Highlighted_Trace $a
	gtkwave::/Edit/UnHighlight_All $a
}

