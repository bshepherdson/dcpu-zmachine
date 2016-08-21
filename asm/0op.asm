; 0OP opcodes for the Z-machine.

; Table of these opcodes.
:ops_0op
dat op_rtrue
dat op_rfalse
dat op_print
dat op_print_ret
dat op_nop
dat op_save_old
dat op_restore_old
dat op_restart
dat op_ret_popped
dat op_pop_or_catch
dat op_quit
dat op_new_line
dat op_show_status
dat op_verify
; No op 14; it's the first byte of the extended opcode.
dat unrecognized_opcode
dat op_piracy


:op_rtrue
set a, 1
set pc, zreturn

:op_rfalse
set a, 0
set pc, zreturn

; Prints the literal string following this opcode, at PC.
:op_print
set pc, print_pc

:op_print_ret
jsr print_pc
set a, 1
set pc, zreturn

:op_nop
set pc, pop

; This 0OP version of save is a branch in v1-3, a store in v4, illegal in v5.
:op_save_old
ifg [version], 4
  set pc, L0000
ife [version], 4
  set pc, L0001

; v1-3, so this is a branch.
; We always return "false", meaning the save failed.
set a, 0
set pc, zbranch

:L0001 ; v4, store instruction
set a, 0 ; "failure"
set pc, zstore

:L0000 ; v5 illegal instruction
set a, msg_illegal_opcode
set pc, emit_native_string



; This 0OP version of restore is the same API as save above.
:op_restore_old
ifg [version], 4
  set pc, L0002
ife [version], 4
  set pc, L0003

; v1-3, so this is a branch.
; The branch is never actually made - a successful restore is running after the
; "save", while a failed one doesn't branch.
set a, 0
set pc, zbranch

:L0003 ; v4, store instruction
set a, 0
set pc, zstore

:L0002 ; v5, illegal instruction
set a, msg_illegal_opcode
set pc, emit_native_string


:op_restart
; HACK: Pop the return address off the stack, to prevent deepening.
set a, pop
set pc, zrestart

:op_ret_popped ; Pops from the stack and returns it.
jsr zpop
set pc, zreturn

; In v5 and later, this is "catch". In v4 and earlier, "pop".
:op_pop_or_catch
ifl [version], 5
  set pc, zpop

; Catch. Grabs the "stack frame" such that a future "throw" will return as
; though from this routine.
; This is the number of (DCPU) words from the top of the stack to the current
; fp.
set a, [zfp]
sub a, stack
set pc, zstore


:op_quit
set a, msg_quit
jsr emit_native_string
; TODO If I'm returning control to some kind of OS, do that here.
; Likewise, if I know there's power-control hardware available, use it here.
sub pc, 1

:msg_quit .asciiz "Quitting."

:op_new_line
set pc, new_line


; TODO Actually print the status lines for the various versions.
; This needs careful support of the terminal control code.
:op_show_status
set pc, pop ; No-op for now.

:op_verify ; Always verifies correctly. TODO Implement this as a sanity check.
set a, 1
set pc, zbranch

:op_piracy ; Always returns "authentic", since we're not actually concerned with
           ; piracy here, of course.
set a, 1
set pc, zbranch

