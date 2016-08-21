; Extended opcodes

:ops_extended
dat op_save_new
dat op_restore_new
dat op_log_shift
dat op_art_shift
dat op_set_font
dat unrecognized_opcode ; draw_picture
dat unrecognized_opcode ; picture_data
dat unrecognized_opcode ; erase_picture
dat unrecognized_opcode ; set_margins
dat op_save_undo
dat op_restore_undo
dat unrecognized_opcode ; print_unicode
dat unrecognized_opcode ; check_unicode
dat unrecognized_opcode ; set_true_colour_foreground
dat unrecognized_opcode
dat unrecognized_opcode
dat unrecognized_opcode
dat unrecognized_opcode
dat unrecognized_opcode
dat unrecognized_opcode
dat unrecognized_opcode
dat unrecognized_opcode
dat unrecognized_opcode
dat unrecognized_opcode
dat unrecognized_opcode
dat unrecognized_opcode
dat unrecognized_opcode
dat unrecognized_opcode

:op_save_new
set a, 0
set pc, zstore ; 0 for failure

:op_restore_new
set a, 0
set pc, zstore

:op_log_shift ; (number, places)
set a, [var_args]
set b, [var_args+1]

ifu b, 0 ; Negative shift
  set pc, L4000

; Positive case: shift left
shl a, b
set pc, zstore

:L4000
; Negate B
xor b, -1
add b, 1
shr a, b
set pc, zstore

:op_art_shift ; (number, places)
set a, [var_args]
set b, [var_args+1]

ifu b, 0 ; Negative shift
  set pc, L4010

; Positive case: shift left
shl a, b
set pc, zstore

:L4010
; Negate B
xor b, -1
add b, 1
asr a, b
set pc, zstore

:op_set_font ; No requested font is available - return 0.
set a, 0
set pc, zstore

:op_save_undo ; Returns -1 when unable to provide the feature.
set a, -1
set pc, zstore

:op_restore_undo ; Returns -1 again.
set a, -1
set pc, zstore

