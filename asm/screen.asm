; This is the generic screen API and shared globals.
; You need to include this file, and one of the lem.asm, imva.asm or printer.asm
; to actually implement it.


; The actual screen API that all backends should support is:
; init_screen()     ; Called at setup.
; emit(c)           ; Writes a single character.
; clear_screen()    ; Clears the screen.
; erase_window(win) ; Erases the top or bottom window.
; erase_to_eol()    ; Erases to the end of the current line.
; new_line()        ; Advances to a new line.

; This is the abstraction layer that calls through the indirected pointers.
; At load time, we choose the best display (IMVA > printer > LEM) and sets up
; this vtable accordingly.

:init_screen
set pc, [_init_screen]
:emit
set pc, [_emit]
:clear_screen
set pc, [_clear_screen]
:erase_window
set pc, [_erase_window]
:erase_to_eol
set pc, [_erase_to_eol]
:new_line
set pc, [_new_line]

:screen_cols .dat 0
:screen_rows .dat 0

:_init_screen .dat 0
:_emit .dat 0
:_clear_screen .dat 0
:_erase_window .dat 0
:_erase_to_eol .dat 0
:_new_line .dat 0

; Table of colour mappings. Indexed by Z-machine colours, values are LEM colours
:colour_table
dat 0 ; 0 = "current"
dat 0 ; 1 = "default"
dat 0 ; 2 = black
dat 4 ; 3 = red (LEM dark red)
dat 2 ; 4 = green (LEM dark green)
dat 6 ; 5 = yellow (LEM dark yellow)
dat 1 ; 6 = blue (LEM dark blue)
dat 5 ; 7 = magenta (LEM dark pink)
dat 3 ; 8 = cyan (LEM dark cyan)
dat 8 ; 9 = white (LEM light grey)

:text_style dat 0 ; Defaults to Roman, no special styles.
.def text_style_reverse, 1
.def text_style_bold, 2
.def text_style_italic, 4
.def text_style_fixed, 8

:text_fg dat 9 ; Z-machine values, default foreground is white.
:text_bg dat 2 ; Z-machine values, default background is black.


; Each window has its own cursor. However, the upper window cursor is reset to
; (0,0) immediately whenever it's selected. Therefore it doesn't have to be
; saved.

; These are the current, real, dynamic cursors.
:cursor_row DAT 0
:cursor_col DAT 0

; These are the saved lower-window cursors. When the lower window is selected,
; these are out of date.
:saved_cursor_row dat 0
:saved_cursor_col dat 0

; Gives the current window. 0 is the lower window, 1 is the top window.
:window dat 0
.def window_bottom, 0
.def window_top, 1

; Gives the number of lines devoted to the top window. The top window is
; excluded from scrolling.
:top_window_size dat 0


; Emits a C-style null-terminated string. This is a universal library,
; it doesn't care what the underlying display is.
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


:emit_number_buffer .reserve 8
:emit_number_buffer_end

; Emits a signed, decimal number.
; This is a universal library, it works for every display backend.
:emit_number ; (num) -> void
ifu a, 0
  set pc, L160
; Positive case
set push, 0
set pc, L161

:L160 ; Negative case
set push, 1
xor a, -1
add a, 1 ; Now it's the positive equivalent.

:L161 ; Continuing on.
set b, emit_number_buffer_end
:L162
sub b, 1
set c, a
mod c, 10 ; C is the remainder, ie. the next digit to store.
add c, 48 ; Now C is the character code.
set [b], c

div a, 10
ifn a, 0
  set pc, L162

; Now we've loaded the entire number into the buffer.
; Add a negative sign if necessary.
set a, pop
ife a, 0
  set pc, L163

; Write the negative sign.
sub b, 1
set [b], 45 ; '-'

:L163 ; Now B is pointing at the first character, so loop and emit.
ife b, emit_number_buffer_end
  set pc, L164
set push, b
set a, [b]
jsr emit
set b, pop
add b, 1
set pc, L163

:L164 ; Done the loop, all done with this function.
set pc, pop

