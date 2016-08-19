; Overall design for the DCPU Z-machine interpreter.
;
; 1. Memory
; The DCPU has 64K words of memory, which is 128KB. Z-machine games are limited
; to a maximum of 64KB of dynamic memory.
; Therefore for simplicity, we simply allocate the upper half of the DCPU's
; address space for the dynamic memory, starting at 0x8000.
;
; Meanwhile, routines and strings are stored higher up in the story file, and
; accessed more rarely.
; To that end, I'll maintain as many sectors of lower memory as seem reasonable,
; and use them to cache higher memory from the story file.
;
; Since that memory is not writeable anyway, there are no concerns about it
; being dirty.
;
; 2. Calling convention and register allocation
; A, B, and C are the parameters.
; X, Y, Z, I, and J are usable, but need to be preserved.

; First instruction
set pc, main

; Some globals that drive the whole system.
:version
DAT 0

; The Z-machine PC is two words wide, since it's routinely above 64K.
:zpc
DAT 0, 0

; 256-cell stack
:stack .reserve 256
:zsp dat stack+256
:zfp dat 0



; Treating the stack as full-descending, aka decrement-before-store
:zpush ; (x) -> void
sub [zsp], 1
set b, [zsp]
set [b], a
set pc, pop

:zpop ; () -> x
set b, [zsp]
set a, [b]
add b, 1
set [zsp], b
set pc, pop

:zpeek ; () -> x
set a, [zsp]
set a, [a]
set pc, pop



; Constants for the header
.def header_version,    0x0000
.def header_flags1,     0x0001
.def header_himem,      0x0004
.def header_initial_pc, 0x0006
.def header_dictionary, 0x0008
.def header_obj_table,  0x000a
.def header_globals,    0x000c
.def header_static,     0x000e
.def header_flags2,     0x0010
.def header_abbreviations, 0x0018
.def header_file_length,   0x001a
.def header_checksum,      0x001c
; TODO Finish up the header.

