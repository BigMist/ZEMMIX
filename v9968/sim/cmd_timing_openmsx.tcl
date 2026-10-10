after time 120 exit
set mute on
set renderer none
set throttle off
# V9968 command timing reference (ZEMMIX-f7c.3): the commands of
# v9968/sim/cmd_timing_tb.v in openMSX (master; Docker image openmsx-master),
# SCREEN 5 set through the debugger with the CPU halted (DI; HALT), each
# started at VR 1 -> 0, CE polled; results in /work/res.txt (V9938 cycles).
#   timeout 150 docker run --rm -v $PWD/f7c3:/work -v $PWD/share:/root/.openMSX/share \
#     -w /work openmsx-master:latest openmsx -machine Zemmix_turboR -script /work/cmd_timing_openmsx.tcl
proc out {s} { set f [open /work/res.txt a]; puts $f $s; close $f }
proc vw {r v} { debug write "VDP regs" $r $v }
#           name   SX  SY  DX  DY  NX  NY  COL  ARG  R46
set tests {
  HMMV      0   0   0   0 256 212 0x11 0x00 0xC0
  HMMM      0   0   0 256 256  64 0x00 0x00 0xD0
  YMMM      0  10   0 400   0  64 0x00 0x00 0xE0
  LMMV      0   0   0   0 256  64 0x05 0x00 0x82
  LMMM      0   0   0 300 256  64 0x00 0x00 0x93
  LINE      0   0  10  10 200 100 0x07 0x00 0x70
  LINEY     0   0  10  10 200 100 0x08 0x01 0x70
  SRCH      0   0   0   0   0   0 0x02 0x00 0x60
  PSET      0   0 100 100   0   0 0x09 0x00 0x50
  POINT   100 100   0   0   0   0 0x00 0x00 0x40
  HMMC      0   0  32 200  16  16 0x21 0x00 0xF0
  LMMC      0   0  64 200  16  16 0x03 0x00 0xB0
}
set modes {0 1 2}
set ti 0
set mi 0
proc setmode {} {
  set m [lindex $::modes $::mi]
  vw 0 0x06; vw 1 [expr {$m == 0 ? 0x00 : 0x40}]; vw 8 [expr {$m == 1 ? 0x0A : 0x08}]
  vw 9 0x80; vw 2 0x1F; vw 5 0xEF; vw 11 0; vw 6 0x0F; vw 14 0
  set ::ti 0
  after time 0.05 go
}
proc w16 {r v} { vw $r [expr {$v & 255}]; vw [expr {$r+1}] [expr {$v >> 8}] }
proc go {} {
  if {$::ti >= [llength $::tests]} {
    incr ::mi
    if {$::mi < [llength $::modes]} { setmode } else { out "done"; exit }
    return
  }
  lassign [lrange $::tests $::ti [expr {$::ti+9}]] name sx sy dx dy nx ny col arg r46
  set ::name $name
  w16 32 $sx; w16 34 $sy; w16 36 $dx; w16 38 $dy; w16 40 $nx; w16 42 $ny; vw 44 $col; vw 45 $arg
  set ::r46 $r46
  set ::vrstate 0
  vrwait
}
proc vrwait {} {
  set vr [expr {[debug read "VDP status regs" 2] & 0x40}]
  if {$::vrstate == 0} { if {$vr} { set ::vrstate 1 }; after time $::dt vrwait; return }
  if {$vr} { after time $::dt vrwait; return }
  set ::t0 [machine_info time]
  vw 46 $::r46
  set ::last $::t0
  set ::nb 1
  after time $::dt poll
}
set dt [expr {4.0/21477270}]
proc poll {} {
  set s [debug read "VDP status regs" 2]
  if {!($s & 1)} { done; return }
  if {($::r46 == 0xF0 || $::r46 == 0xB0) && ($s & 0x80) && (([machine_info time] - $::last) * 21477270 >= 139.5)} {
    set ::last [machine_info time]
    vw 44 [expr {(0x30 + $::nb) & 255}]
    incr ::nb
  }
  after time $::dt poll
}
proc done {} {
  set d [expr {round(([machine_info time] - $::t0) * 21477270)}]
  out "RESULT mode=[lindex $::modes $::mi] $::name $d ($::nb)"
  incr ::ti 10
  after time 0.01 go
}
proc setup {} {
  debug write memory 0xC000 0xF3
  debug write memory 0xC001 0x76
  reg pc 0xC000
  setmode
}
after time 8 setup
