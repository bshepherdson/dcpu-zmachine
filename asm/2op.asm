; 2OP opcodes for DCPU Z-machine interpreter.
; 2OP opcodes expect their arguments as A and B.

:ops_2op
dat 0 ; 0 is special and can't actually be encoded here.
dat op_je_2op
dat op_jl
dat op_jg
dat op_dec_chk
dat op_inc_chk
dat op_jin
dat op_test
dat op_or
dat op_and
dat op_test_attr
dat op_set_attr
dat op_clear_attr
dat op_store
dat op_insert_obj
dat op_loadw
dat op_loadb
dat op_get_prop
dat op_get_prop_addr
dat op_get_next_prop
dat op_add
dat op_sub
dat op_mul
dat op_div
dat op_mod
dat op_call_2s
dat op_call_2n
dat op_set_colour
dat op_throw


:op_je_2op ; This 2OP version can only be called with 2 real args.
set c, 0
ife a, b
  set c, 1
set a, c
set pc, zbranch

:op_jl ; Uses signed comparison.
set c, 0
ifu a, b
  set c, 1
set a, c
set pc, zbranch


:op_jg
set c, 0
ifa a, b
  set c, 1
set a, c
set pc, zbranch

; Decrements the value in the given variable reference (A), then branches if it
; is now less than B. (signed)
:op_dec_chk
set push, b
set push, a ; Save the values
jsr read_variable ; A is now the value of the variable.
sub a, 1
set b, a
set a, pop  ; Pop the variable reference.
set push, b ; Save the new value.
jsr write_variable
set a, pop  ; A is the new value.
set b, pop  ; B is the original B.
; We branch when the new value (A) is less than the limit (B); signed.
set c, 0
ifu a, b
  set c, 1
set a, c
set pc, zbranch


; Increments the value in the given variable reference (A), then branches if it
; is now greater than B. (signed)
:op_inc_chk
set push, b
set push, a ; Save the values
jsr read_variable ; A is now the value of the variable.
add a, 1
set b, a
set a, pop  ; Pop the variable reference.
set push, b ; Save the new value.
jsr write_variable
set a, pop  ; A is the new value.
set b, pop  ; B is the original B.
; We branch when the new value (A) is greater than the limit (B); signed.
set c, 0
ifa a, b
  set c, 1
set a, c
set pc, zbranch

:op_jin ; Branches when object A is a direct child of B.
; Look up the parent of A.
set push, b
jsr zobj_addr
set b, [zobj_offset_parent]
jsr zobj_read_relative ; A is now the parent of the original object A.
set c, 0
ife a, pop
  set c, 1
set a, c
set pc, zbranch


:op_test ; A is a value, B is the test. Essentially : A&B == B
and a, b
set c, 0
ife a, b
  set c, 1
set a, c
set pc, zbranch

:op_or
bor a, b
set pc, zstore

:op_and
and a, b
set pc, zstore

:op_test_attr ; (obj_num, attr)
jsr zobj_test_attr
set pc, zbranch


:op_set_attr ; (obj_num, attr)
set pc, zobj_set_attr

:op_clear_attr ; (obj_num, attr)
set pc, zobj_clear_attr

:op_store ; (var_num, value)
set pc, write_variable

:op_insert_obj ; (target, destination)
set pc, zobj_insert_child


:op_loadw ; (array, word-index)
shl b, 1
add a, b ; A is the target byte address.
jsr rwba ; A is now the word found there.
set pc, zstore

:op_loadb ; (array, byte-index)
add a, b
jsr rbba
set pc, zstore


; Read the value of a 1- or 2-byte property.
; Includes the default value if there is such a property.
:op_get_prop ; (obj, prop_num)
; First, try to get the property address for the object.
set push, b
jsr zobj_addr
set b, peek
jsr zobj_get_prop ; A is the address of the property entry, or 0.
ife a, 0
  set pc, L2000 ; Jump to the defaults section.

set b, pop ; Pop off the number, we don't need it anymore on this branch.
; If we got the property, check its length.
set push, a
jsr zobj_prop_size ; A is now the size in bytes.

ife a, 1
  set pc, L2001
ife a, 2
  set pc, L2002

; If we're still here, it's too big.
; That condition is undefined.
; We handle it here by returning 0.
set a, pop
set a, 0
set pc, zstore

:L2001 ; 1 byte
set a, pop
jsr zobj_prop_data ; A is now the data area pointer.
jsr rbba
set pc, zstore
:L2002 ; 2 bytes
set a, pop
jsr zobj_prop_data
jsr rwba
set pc, zstore

:L2000 ; Called when there's no value for that property number. Use the defaults
       ; table. The prop number is on the stack.
jsr object_table_base ; A is now the byte address of the defaults table.
set b, pop
sub b, 1
shl b, 1 ; B is now the offset into the table.
add a, b
jsr rwba
set pc, pop ; Returning the default for this property number.


:op_get_prop_addr ; (obj_num, prop_num)
jsr zobj_get_prop
jsr zobj_prop_data
set pc, zstore

:op_get_next_prop ; (obj_num, prop_num)
; If the number is 0, return the number of the first property.
ife b, 0
  set pc, L2010

; Otherwise, get the property entry for num, then the next one, then its number.
set push, b
jsr zobj_addr
set b, pop
jsr zobj_get_prop
jsr zobj_next_prop
jsr zobj_prop_num
set pc, zstore

:L2010 ; Special case of getting the first property's number.
jsr zobj_addr
jsr zobj_first_prop
jsr zobj_prop_num
set pc, zstore


:op_add
add a, b
set pc, zstore

:op_sub
sub a, b
set pc, zstore

:op_mul
mli a, b
set pc, zstore

; TODO Catch and error on B = 0
:op_div
dvi a, b
set pc, zstore

:op_mod
mdi a, b
set pc, zstore

; Using the var_args fields for the args array.
:op_call_2 ; (pa, arg, return-expected?) -> void
set push, x
set push, y

set x, var_args
set [x], b
set y, c

jsr pa_la ; A:B is now the long address.
set c, 1  ; 1 arg
; X and Y are already correctly set.
jsr zcall
set y, pop
set x, pop
set pc, pop

:op_call_2s
set c, 1
set pc, op_call_2
:op_call_2n
set c, 0
set pc, op_call_2

:op_set_colour
set pc, pop ; TODO implement me

:op_throw ; (value, token)
add b, stack ; B is now the absolute ZFP value.
set [zfp], b ; Override the current one.
set pc, zreturn ; Return A, as though from the routine that ran catch.


