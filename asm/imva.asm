; Implementation of the screen API for the IMVA hardware.
; IMVA is a 1-bit 320x200 display with customizable colour.

; The actual screen API that all backends should support is:
; init_screen()     ; Called at setup.
; emit(c)           ; Writes a single character.
; clear_screen()    ; Clears the screen.
; erase_window(win) ; Erases the top or bottom window.
; erase_to_eol()    ; Erases to the end of the current line.
; new_line()        ; Advances to a new line.

; Embed the LEM font, which is used manually here.
.include asm/font.asm

; LEM pixels are 4x8, so an IMVA using that font is 80x25.
.def imva_screen_cols, 80
.def imva_screen_rows, 25

; 8 pixels per row of text means 4 IMVA lines, 40 words per IMVA row * 4 = 160.
.def imva_words_per_line, 40
.def imva_words_per_row, 160

:imva_vram .reserve 4000 ; This is huge, hopefully there's still room for the code...
:imva_vram_top


:imva_configure
set [_init_screen], imva_init_screen
set [_emit], imva_emit
set [_clear_screen], imva_clear_screen
set [_erase_window], imva_erase_window
set [_erase_to_eol], imva_erase_to_eol
set [_new_line], imva_new_line
set pc, pop

.def display_configure, imva_configure


:imva_init_screen ; () -> void
set a, 0
set b, imva_vram
hwi [hw_imva]

set a, 1
set b, 0 ; Disables overlay.
hwi [hw_imva]

set a, 2
set b, 0x0fff ; Full-contrast white. TODO: Allow customizing.
set c, 0 ; No blink.
hwi [hw_imva]

set pc, pop


:imva_clear_screen ; () -> void
set a, imva_vram
set b, imva_vram_top
:loop
set [a], 0
add a, 1
ifl a, b
  set pc, loop
set pc, pop


:imva_character_buffer .reserve 4
:imva_character_buffer_end

; Pulling bits in the IMVA's order, across a row (4 bits) and down a column,
; this table gives the font word, font mask, IMVA word, and IMVA mask.
; It puts the IMVA data in the left slice of the words.
.def imva_font_lem_word, 0
.def imva_font_lem_mask, 1
.def imva_font_imva_word, 2
.def imva_font_imva_mask, 3
.def imva_font_masking_table_width, 4

:imva_font_masking_table
dat 0, 0x0100, 0, 0x0080 ; (0, 0)
dat 0, 0x0001, 0, 0x0040 ; (0, 1)
dat 1, 0x0100, 0, 0x0020 ; (0, 2)
dat 1, 0x0001, 0, 0x0010 ; (0, 3)
dat 0, 0x0200, 0, 0x8000 ; (1, 0)
dat 0, 0x0002, 0, 0x4000 ; (1, 1)
dat 1, 0x0200, 0, 0x2000 ; (1, 2)
dat 1, 0x0002, 0, 0x1000 ; (1, 3)
dat 0, 0x0400, 1, 0x0080 ; (2, 0)
dat 0, 0x0004, 1, 0x0040 ; (2, 1)
dat 1, 0x0400, 1, 0x0020 ; (2, 2)
dat 1, 0x0004, 1, 0x0010 ; (2, 3)
dat 0, 0x0800, 1, 0x8000 ; (3, 0)
dat 0, 0x0008, 1, 0x4000 ; (3, 1)
dat 1, 0x0800, 1, 0x2000 ; (3, 2)
dat 1, 0x0008, 1, 0x1000 ; (3, 3)
dat 0, 0x1000, 2, 0x0080 ; (4, 0)
dat 0, 0x0010, 2, 0x0040 ; (4, 1)
dat 1, 0x1000, 2, 0x0020 ; (4, 2)
dat 1, 0x0010, 2, 0x0010 ; (4, 3)
dat 0, 0x2000, 2, 0x8000 ; (5, 0)
dat 0, 0x0020, 2, 0x4000 ; (5, 1)
dat 1, 0x2000, 2, 0x2000 ; (5, 2)
dat 1, 0x0020, 2, 0x1000 ; (5, 3)
dat 0, 0x4000, 3, 0x0080 ; (6, 0)
dat 0, 0x0040, 3, 0x0040 ; (6, 1)
dat 1, 0x4000, 3, 0x0020 ; (6, 2)
dat 1, 0x0040, 3, 0x0010 ; (6, 3)
dat 0, 0x8000, 3, 0x8000 ; (7, 0)
dat 0, 0x0080, 3, 0x4000 ; (7, 1)
dat 1, 0x8000, 3, 0x2000 ; (7, 2)
dat 1, 0x0080, 3, 0x1000 ; (7, 3)
:imva_font_masking_table_end

:imva_emit ; (c) -> void
log a
ife a, 0x13
  set pc, imva_new_line

set push, x
set push, y

; Characters are 4x8. That means for each character we're writing 8 bits in 4
; different words.
; First, we examine the font and assemble our character in a 4-word buffer.
; Then we find where it should go, and mix it into the VRAM at that spot.

shl a, 1 ; 2 words per character in the font.
add a, font
set b, [a]
set c, [a+1]

; The orientation of the font characters and the IMVA's raster are completely
; opposite.
; TODO: Probably rewire the font to be in the right orientation.

set [imva_character_buffer], 0
set [imva_character_buffer+1], 0
set [imva_character_buffer+2], 0
set [imva_character_buffer+3], 0

set x, imva_font_masking_table
:imva_emit_font_loop
set a, b
ifg [x + imva_font_lem_word], 0
  set a, c ; A holds the LEM word.

and a, [x + imva_font_lem_mask] ; Now it's masked.
ife a, 0
  set pc, imva_emit_font_loop_continue

; Still here: it's a set bit.
set a, [x + imva_font_imva_word]
bor [a + imva_character_buffer], [x + imva_font_imva_mask]

:imva_emit_font_loop_continue
add x, imva_font_masking_table_width
ifl x, imva_font_masking_table_end
  set pc, imva_emit_font_loop

; Now the character buffer holds the left-column bits.
; So we figure out the base address in VRAM.
set a, [cursor_row]
mul a, imva_words_per_row
set b, [cursor_col] ; That's in characters, which are two to a word here.
set c, b
and c, 1 ; Hang onto the parity bit, we need it later.
shr b, 1
add a, b ; A is now the top-most word to adjust in VRAM.
add a, imva_vram
set b, imva_character_buffer

; A holds the VRAM pointer, B the local one.
:imva_emit_paint_loop
set x, [a]
set y, 0x0f0f ; Mask to preserve the right column.
ife c, 1 ; If odd, shift the mask left.
  shl y, 4
and x, y ; Mask out the other column.

set y, [b] ; The buffered character. It's set up for the left column.
ife c, 1 ; So if it's odd, shift it right.
  shr y, 4
bor x, y ; Mix the characters together.

set [a], x ; Write the final word back to VRAM.
add a, imva_words_per_line
add b, 1
ifl b, imva_character_buffer_end
  set pc, imva_emit_paint_loop

; Finally done emitting this character. Clean up a bit, then adjust the cursor.
set y, pop
set x, pop

set b, [cursor_col]
add b, 1
ife b, imva_screen_cols
  set pc, imva_new_line ; Tail call to new_line, if needed.
set [cursor_col], b
set pc, pop


:imva_new_line ; () -> void
set [cursor_col], 0
set a, [cursor_row]
add a, 1

; Compute the maximum height of the current window.
set b, imva_screen_rows
ife [window], window_top
  set b, [top_window_size]
ifn [window], window_top
  add a, [top_window_size]

ife a, b
  ife [window], window_bottom
    set pc, imva_new_line_bottom

add [cursor_row], 1
set pc, pop

:imva_new_line_bottom ; Reached the bottom of the bottom window.
; We need to actually perform the scrolling.
set pc, imva_scroll


; TODO Some kind of "MORE" functionality to avoid scrolling forever.
; There's no scrollback buffer!
; Scrolls the lower window up by one row.
:imva_scroll ; () -> void
set b, [top_window_size]
mul b, imva_words_per_row
add b, imva_vram ; B is the first line of the scrolling region.
set a, b ; A is the second line.

set c, imva_screen_rows
sub c, [top_window_size]
sub c, 1
mul c, imva_words_per_row ; C is now the number of words to shift.

jsr move
; Now clear the last line.
set a, imva_screen_rows - 1
set pc, imva_clear_line ; Tail call.


; Erases a single line to black space.
:imva_clear_line ; (line) -> void
mul a, imva_words_per_row
add a, imva_vram
set b, a
add b, imva_words_per_row

:imva_clear_line_loop
set [a], 0
add a, 1
ifl a, b
  set pc, imva_clear_line_loop

set pc, pop


:imva_erase_window ; (win) -> void
ifu a, 0
  set pc, imva_erase_window_special_cases

; Non-negative: erase one of the windows.
set push, x
set push, y
set x, 0
set y, [top_window_size] ; Set up for the top window.
ife a, window_top
  set pc, imva_erase_window_loop

; Bottom window.
set x, [top_window_size]
set y, screen_rows

:imva_erase_window_loop
ife x, y
  set pc, imva_erase_window_loop_done
set a, x
jsr imva_clear_line
add x, 1
set pc, imva_erase_window_loop

:imva_erase_window_loop_done ; Done looping, window cleared, so return.
set y, pop
set x, pop
set pc, pop


:imva_erase_window_special_cases
; First, we always clear the whole screen.
set push, a
jsr imva_clear_screen
set a, pop

; But if it's -1, unsplit as well.
ifn a, -1
  set pc, pop ; Done otherwise.

; It is -1, then reset the screen state to a single unsplit window.
set [cursor_row], 0
set [cursor_col], 0
set [window], window_bottom
set [top_window_size], 0
set pc, pop


; TODO: This is expensive, but it works. Keep emitting spaces until
; the line number changes.
:imva_erase_to_eol ; () -> void
set push, x
set push, y
set x, [cursor_row]
set y, [cursor_col]

:imva_erase_to_eol_loop
set a, 32
jsr imva_emit
ifn [cursor_col], 0
  set pc, imva_erase_to_eol_loop

; Done.
set [cursor_col], y
set [cursor_row], x
set y, pop
set x, pop
set pc, pop

