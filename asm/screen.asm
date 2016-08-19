; Hobo version, for testing the string parsers.

; 386 words for the video memory.
.def screen_cols, 32
.def screen_row_shift, 5
.def screen_rows, 12
.def vram_size, screen_cols * screen_rows ; 32 * 12 = 386 words.

:vram
.reserve vram_size
:vram_top

.def green_on_black, 0xa000
.def blank_space, 0xa020

:cursor_row DAT 0
:cursor_col DAT 0


:init_screen ; () -> void
jsr clear_screen

set a, 0
set b, vram
hwi [hw_display]
set pc, pop

:emit ; (c) ->
ife a, 0x13
  set pc, new_line
set b, [cursor_row]
shl b, screen_row_shift ; 32 characters per row.
add b, [cursor_col]
add b, vram
bor a, green_on_black
set [b], a

set b, [cursor_col]
add b, 1
ife b, screen_cols
  set pc, new_line ; Tail call to new_line.
set [cursor_col], b
set pc, pop


; Emits a C-style null-terminated string.
:emit_native_string ; (addr) -> void
set push, x
set x, a
:L110
set a, [x]
ife a, 0
  set pc, L111
jsr emit
add x, 1
set pc, L110
:L111
set x, pop
set pc, pop


; Erases the screen to all black space.
:clear_screen ; () -> void
set a, vram
:L90
set [a], blank_space
add a, 1
ifl a, vram_top
  set pc, L90
set [cursor_row], 0
set [cursor_col], 0
set pc, pop



:new_line ; () -> void
set [cursor_col], 0
set a, [cursor_row]
add a, 1
ife a, 12
  set pc, scroll     ; Tail call to scroll. Leaves the cursor on this row.
set [cursor_row], a
set pc, pop


; Move everything up by a row.
:scroll ; () -> void
set a, vram + screen_cols ; Second line
set b, vram               ; First line
set c, vram_size          ; Size of VRAM
set pc, move              ; Tail call to move()
