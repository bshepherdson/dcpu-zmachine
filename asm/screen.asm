; Hobo version, for testing the string parsers.

; 386 words for the video memory.
.def screen_cols, 32
.def screen_row_shift, 5
.def screen_rows, 12
.def vram_size, screen_cols * screen_rows ; 32 * 12 = 386 words.

:vram
.reserve vram_size
:vram_top

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

:style_char ; (char) -> LEM word
and a, 0x7f ; Get just the character.
set b, [text_fg]
set b, [b + colour_table] ; B is now the LEM colour for foreground.
shl b, 12 ; Shift it up to the top nybble.
bor a, b

set b, [text_bg]
set b, [b + colour_table] ; B is now the LEM colour for background.
shl b, 8 ; Shift to second nybble.
bor a, b

; A is now the full word, minus any styling.
; For BOLD, we activate the blink bit (7)
ifb [text_style], text_style_bold
  bor a, 0x80 ; Mix in the blink bit.

ifc [text_style], text_style_reverse ; If NOT reverse, skip over the next bit.
  set pc, L6100

set c, a
and c, 0xf000
shr c, 4
set b, a
and b, 0x0f00
shl b, 4
bor b, c
and a, 0xff
bor a, b ; Mix them all back together.

:L6100
set pc, pop


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


:init_screen ; () -> void
jsr clear_screen

set a, 0
set b, vram
hwi [hw_display]
set pc, pop

:emit ; (c) ->
ife a, 0x13
  set pc, new_line
jsr style_char ; A is now a styled word.
set b, [cursor_row]
shl b, screen_row_shift ; 32 characters per row.
add b, [cursor_col]
add b, vram
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


:emit_number_buffer .reserve 8
:emit_number_buffer_end

; Emits a signed, decimal number.
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



; Erases the screen to all black space.
:clear_screen ; () -> void
set push, x
set a, 32 ; space
jsr style_char ; A is now the full word.
set x, a

set a, vram
:L90
set [a], x
add a, 1
ifl a, vram_top
  set pc, L90
set x, pop
set pc, pop


; Erases a single line to black space.
:clear_line ; (line) -> void
set push, a
set a, 32 ; space
jsr style_char
set c, a  ; C is now the styled, coloured space.
set a, pop

shl a, screen_row_shift
add a, vram
set b, a
add b, screen_cols
:L95
set [a], c
add a, 1
ifl a, b
  set pc, L95
set pc, pop


; Erases the current line from the cursor position to the end.
:erase_to_eol ; () -> void
set a, 32
jsr style_char ; A is the styled word for a space.

set b, [cursor_row]
shl b, screen_row_shift
add b, vram ; B is the start of the current line.
set c, b
add c, screen_cols ; C is now the end of the current line.
add b, [cursor_col] ; B is the current cursor position.

:L6010
ife b, c
  set pc, pop ; We're done.
set [b], a
add b, 1
set pc, L6010



:new_line ; () -> void
set [cursor_col], 0
set a, [cursor_row]
add a, 1

; Compute the maximum height of the current window.
set b, 12
ife [window], window_top
  set b, [top_window_size]
ifn [window], window_top
  sub b, [top_window_size]

ife a, b
  ife [window], window_bottom
    set pc, L170

set [cursor_row], a
set pc, pop

:L170 ; Reached off the bottom of a window.
; If we're in the non-scrolling top window, do nothing. cursor_row stays on this
; row.
; If we're in the scrolling bottom window, scroll it and keep the cursor on the
; bottom row.

ife [window], window_top
  set pc, pop
; Tail call to scroll.
set pc, scroll



; TODO Support "MORE" functionality to avoid an unscrollable wall of text.
; Move the lower window up by a row.
:scroll ; () -> void
set b, [top_window_size]
shl b, screen_row_shift
add b, vram ; B is the first line.
set a, b
add a, screen_cols ; A is the second line.

set c, screen_rows
sub c, [top_window_size]
sub c, 1
shl c, screen_row_shift ; C is now the number of words to be shifted.
                        ; That's the lines of the lower window, minus 1.
jsr move
; Now clear the last line.
set a, screen_rows - 1
set pc, clear_line ; Tail call to clear_line()

