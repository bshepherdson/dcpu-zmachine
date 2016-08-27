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

; A settable breakpoint, which will halt execution.
:zbreak
dat 0, 0x0

; 256-cell stack
:zsp dat stack_top
:zfp dat 0
:stack .reserve 256
:stack_top
dat 0xdead, 0xbeef ; Sentinels to guard against being overwritten.



; Treating the stack as full-descending, aka decrement-before-store
:zpush ; (x) -> void
set b, [zsp]
sub b, 1
set [b], a
set [zsp], b
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

:zpeek_write ; (value) -> void
set b, [zsp]
set [b], a
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
.def header_interpreter_number, 0x001e
.def header_interpreter_version, 0x001f
.def header_screen_height_lines, 0x0020
.def header_screen_width_chars, 0x0021
.def header_screen_width_units, 0x0022
.def header_screen_height_units, 0x0024
.def header_font_width_units, 0x0026
.def header_font_height_units, 0x0027
.def header_default_bg_colour, 0x002c
.def header_default_fg_colour, 0x002d
.def header_standard_revision, 0x0032

