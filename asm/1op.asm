; 1OP opcodes for the Z-machine.

:ops_1op
dat op_jz
dat op_get_sibling
dat op_get_child
dat op_get_parent
dat op_get_prop_len
dat op_inc
dat op_dec
dat op_print_addr
dat op_call_1s
dat op_remove_obj
dat op_print_obj
dat op_ret
dat op_jump
dat op_print_paddr
dat op_load
dat op_not_or_call_1n

:op_jz ; Jumps is A is 0
set b, 0
ife a, 0
  set b, 1
set a, b
set pc, zbranch


; These three take an object number, and store the object number in the
; sibling/child/parent slot.
; get_sibling and get_child additionally branch if there is such an object.
:op_get_sibling
jsr zobj_addr ; A is now the address of the object itself.
set b, [zobj_offset_sibling]
jsr zobj_read_relative ; A is now the relative's number.
set push, a
jsr zstore ; Store it
set a, pop
set pc, zbranch ; Tail call branch.

:op_get_child
jsr zobj_addr ; A is now the address of the object itself.
set b, [zobj_offset_child]
jsr zobj_read_relative ; A is now the relative's number.
set push, a
jsr zstore ; Store it
set a, pop
set pc, zbranch ; Tail call branch.

:op_get_parent
jsr zobj_addr ; A is now the address of the object itself.
set b, [zobj_offset_parent]
jsr zobj_read_relative ; A is now the relative's number.
set pc, zstore ; Store it (tail call)

; A here is the byte address of an object's property's data.
; This returns the length of the data field.
; Requires working backward.
; Returns 0 when passed 0, as a special case.
:op_get_prop_len
ife a, 0 ; Special case: if passed 0, returns 0 immediately.
  set pc, zstore

; Otherwise we work backward from the data address to the original property.
jsr zobj_prop_data_to_prop ; A is now the property address itself.
jsr zobj_prop_size
set pc, zstore

; A is the variable *number*. Read it, bump it, store it again.
:op_inc
set push, a
jsr read_variable
add a, 1
set b, a
set a, pop
set pc, write_variable

:op_dec
set push, a
jsr read_variable
sub a, 1
set b, a
set a, pop
set pc, write_variable

; A is a byte address of a target string.
:op_print_addr
set pc, print_ba

; Calls a routine with no arguments.
:op_call_1s
set push, x
set push, y
jsr pa_la ; A:B is now the routine's long address.
set c, 0  ; No arguments.
set x, 0  ; Null argument array.
set y, 1  ; Return is expected
jsr zcall
set y, pop
set x, pop
set pc, pop


; Given an object's number, remove it from the tree to stand alone.
:op_remove_obj
set pc, zobj_remove

:op_print_obj
jsr zobj_addr
jsr zobj_short_name ; A is the byte address now.
jsr print_ba

:op_ret
set pc, zreturn

; This is NOT a branch instruction. The argument is a two-byte signed offset to
; the PC.
; The offset needs a sub 2 first, but it doesn't support the rtrue, rfalse
; special cases. I think? TODO Check that.
:op_jump
sub a, 2
set pc, branch_signed ; Tail call to this function.

:op_print_paddr ; A is a paddr, print it.
set pc, print_paddr

; A is a variable number. NB: If A is 0, we /peek/ the stack rather than pop it.
:op_load
set b, read_variable
ife a, 0
  set b, zpeek
jsr b
set pc, zstore


; In v1-4 this is "not", a store instruction that does bitwise inversion.
; In v5+ this is "call_1n", a non-storing, 0-argument call.
:op_not_or_call_1n
ifg [version], 4
  set pc, L1010

; v1-4, so this is "not".
xor a, -1 ; Flip all the bits.
set pc, zstore

:L1010 ; v5+, this is "call_1n"
set push, x
set push, y
jsr pa_la ; A:B is now the long address.
set c, 0  ; C=0 is the arg count.
set x, 0  ; X=null is the argument array.
set y, 0  ; Y=false means no return expected.
jsr zcall
set y, pop
set x, pop
set pc, pop


