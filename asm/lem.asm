; LEM1802 implementation of the screen systems.

; The actual screen API that all backends should support is:
; configure()       ; Set up the vectors properly.
; init_screen()     ; Called at setup.
; emit(c)           ; Writes a single character.
; clear_screen()    ; Clears the screen.
; erase_window(win) ; Erases the top or bottom window.
; erase_to_eol()    ; Erases to the end of the current line.
; new_line()        ; Advances to a new line.

; This file implements that API for the LEM1802, which mostly doesn't work.
; The LEM is only 32 characters wide, which is not enough for most games.
; asm/printer.asm implements it for printers, and asm/imva.asm for IMVA.
; Include only one of the three in main.asm, along with screen.asm.

; 386 words for the video memory.
.def lem_screen_cols, 32
.def screen_row_shift, 5
.def lem_screen_rows, 12
.def vram_size, lem_screen_cols * lem_screen_rows ; 32 * 12 = 386 words.

:vram
.reserve vram_size
:vram_top


:lem_configure
set [_init_screen], lem_init_screen
set [_emit], lem_emit
set [_clear_screen], lem_clear_screen
set [_erase_window], lem_erase_window
set [_erase_to_eol], lem_erase_to_eol
set [_new_line], lem_new_line
set pc, pop

.def display_configure, lem_configure



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



:lem_init_screen ; () -> void
set [screen_rows], lem_screen_rows
set [screen_cols], lem_screen_cols

jsr clear_screen

set a, 0
set b, vram
hwi [hw_display]
set pc, pop

:lem_emit ; (c) ->
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



; Erases the screen to all black space.
:lem_clear_screen ; () -> void
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
:lem_clear_line ; (line) -> void
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

; Erases the given window. Called from the op.
:lem_erase_window ; (win)
ifu a, 0
  set pc, L4080

; Non-negative: erase one of the windows.
set push, x
set push, y
set x, 0
set y, [top_window_size] ; Set up for the top window.
ife a, window_top ; Actually top window.
  set pc, L4081

; Bottom window.
set x, [top_window_size]
set y, screen_rows

:L4081 ; Loop until X == Y
ife x, y
  set pc, L4082
set a, x
jsr lem_clear_line
add x, 1
set pc, L4081

:L4082 ; Done looping, window cleared, so bail.
set y, pop
set x, pop
set pc, pop

:L4080 ; Special cases.
; The whole screen is always cleared.
set push, a
jsr lem_clear_screen
; But we unsplit when it's -1

set a, pop
ifn a, -1
  set pc, pop ; Done.

; If it is -1, then we reset the screen state as well.
set [cursor_row], 0
set [cursor_col], 0
set [window], window_bottom
set [top_window_size], 0
set pc, pop


; Erases the current line from the cursor position to the end.
:lem_erase_to_eol ; () -> void
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



:lem_new_line ; () -> void
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
set pc, lem_scroll



; TODO Support "MORE" functionality to avoid an unscrollable wall of text.
; Move the lower window up by a row.
:lem_scroll ; () -> void
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
set pc, lem_clear_line ; Tail call to lem_clear_line()

