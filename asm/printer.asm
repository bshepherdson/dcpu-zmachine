; Implements the generic output driver API for a HSDP-1D printer.

; That doesn't allow cursor addressing. Buffers 80 characters and then outputs
; them as a single line.

.def hsdp_int_mode, 0
.def hsdp_int_print, 3

.def hsdp_blank, 0x20 ; space
.def hsdp_len, 80

.def hsdp_rows, 0x0 ; Kind of wonky, since it's infinite.
.def hsdp_cols, 80  ; 80 columns in text mode.

:printer_configure
set [_init_screen], printer_init_screen
set [_emit], printer_emit
set [_clear_screen], printer_clear_screen
set [_erase_window], printer_erase_window
set [_erase_to_eol], printer_erase_to_eol
set [_new_line], printer_new_line
set pc, pop

.def display_configure, printer_configure


:hsdp_init_screen ; () -> void
; Put the printer into mode 0, text mode.
set [screen_rows], hsdp_rows
set [screen_cols], hsdp_cols

set a, hsdp_int_mode
set b, 0
hwi [hw_printer]

set hsdp_pointer, hsdp_buffer

; Clear the buffer.
set pc, _hsdp_clear_buffer


:hsdp_buffer .reserve hsdp_len
:hsdp_buffer_end
:hsdp_pointer .dat 0

:_hsdp_clear_buffer ; () ->
set c, hsdp_len
set a, hsdp_buffer
:L8001
set [a], hsdp_blank
add a, 1
sub c, 1
ifg c, 0
  set pc, L8001

set [hsdp_pointer], hsdp_buffer
set pc, pop


:hsdp_emit ; (c) ->
set c, hsdp_pointer
set b, [c]
set [b], a
add b, 1
set [c], b
ife b, hsdp_buffer_end
  set pc, hsdp_new_line ; tail call
set pc, pop

; Actually prints the currently buffered text.
:hsdp_new_line ; ()
set a, hsdp_int_print
set b, hsdp_buffer
hwi [hw_printer]
set pc, _hsdp_clear_buffer ; tail call


:hsdp_clear_screen ; ()
set pc, _hsdp_clear_buffer ; tail call, just scrap the buffer.

:hsdp_erase_window ; (win)
set pc, pop ; no-op, can't actually erase.

:hsdp_erase_to_eol ; ()
set pc, pop ; no-op, can't actually erase.

