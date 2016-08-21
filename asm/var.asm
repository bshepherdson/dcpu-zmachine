; VAR opcode implementations.

:ops_var
dat op_call_vs
dat op_storew
dat op_storeb
dat op_put_prop
dat op_sread
dat op_print_char
dat op_print_num
dat op_random
dat op_push
dat op_pull
dat op_split_window
dat op_set_window
dat op_call_vs2
dat op_erase_window
dat op_erase_line
dat op_set_cursor
dat op_get_cursor
dat op_set_text_style
dat op_buffer_mode
dat op_output_stream
dat op_input_stream
dat op_sound_effect
dat op_read_char
dat op_scan_table
dat op_not
dat op_call_vn
dat op_call_vn2
dat op_tokenise
dat op_encode_text
dat op_copy_table
dat op_print_table
dat op_check_arg_count

; The VAR opcodes expect their args in [var_args] and the count in [var_count].

; Helper for call_v[sn](2)
:op_call_helper ; (expect_return?) -> void
set push, x
set push, y
set push, a ; Save the return-expected flag for later.
set a, [var_args]
jsr pa_la ; A:B is now the packed address.

set c, [var_count]
sub c, 1 ; Remove 1, it's the address.
set x, var_args+1 ; Skip over the routine address.
set y, pop ; Return-expected
jsr zcall
set y, pop
set x, pop
set pc, pop

:op_call_vs
set a, 1
set pc, op_call_helper

:op_storew ; (array, word-index, value)
set a, [var_args+1]
shl a, 1 ; Byte offset.
add a, [var_args] ; Absolute byte address.
set b, [var_args+2] ; The value
set pc, wwba

:op_storeb ; (array, byte-index, value)
set a, [var_args]
add a, [var_args+1]
set b, [var_args+2]
set pc, wbba

; Four cases:
; 1. Property not found - error message.
; 2. 1-byte property - write least-significant byte.
; 3. 2-byte property - write whole word.
; 4. Longer property - undefined (error message for sanity-checking)
:op_put_prop ; (obj_num, prop_num, value)
set a, [var_args]
jsr zobj_addr ; A is now the object's address.
set b, [var_args+1]
jsr zobj_get_prop ; A is now the property entry, or 0.

ife a, 0
  set pc, L3000 ; No such property.

; Now check the size.
set push, a
jsr zobj_prop_size ; A is the size in bytes.

ife a, 1
  set pc, L3001 ; 1-byte case
ife a, 2
  set pc, L3002 ; 2-byte case

; Longer than 2 bytes, emit an error message.
set a, pop
set a, msg_put_prop_too_long
set pc, emit_native_string


:L3001 ; 1-byte case. ( ... prop-addr )
set a, pop
jsr zobj_prop_data ; A is now the data pointer.
set b, [var_args+2] ; B is the value.
set pc, wbba ; Tail call

:L3002 ; 2-byte case ( ... prop-addr )
set a, pop
jsr zobj_prop_data ; A is data pointer.
set b, [var_args+2]
set pc, wwba

:L3000 ; No such property (stack is clean here)
set a, msg_put_prop_not_found
set pc, emit_native_string

:msg_put_prop_too_long  .asciiz "[put_prop: Property too long]"
:msg_put_prop_not_found .asciiz "[put_prop: Property not found]"


; TODO Implement me!
:op_sread
sub pc, 1

:op_print_char ; (char)
set a, [var_args]
set pc, emit

:op_print_num ; (value)
set a, [var_args]
set pc, emit_number

:op_random ; (range)
set a, [var_args]
ifu a, 0 ; Negative means seed to that.
  set pc, L3003

; Generate a number from 1-N
jsr random
set pc, zstore

:L3003 ; Seed our generator.
; TODO When A=0 I should re-seed the generator with entropy.
set b, 0
jsr seed
set a, 0
set pc, zstore


:op_push ; (val)
set a, [var_args]
set pc, zpush

:op_pull ; (var_num)
jsr zpop ; A is now the value.
set b, a
set a, [var_args]
set pc, write_variable


; TODO Implement these window and I/O ops.
:op_split_window
:op_set_window
:op_erase_window
:op_erase_line
:op_set_cursor
:op_get_cursor
:op_set_text_style
:op_buffer_mode
:op_output_stream
:op_input_stream


:op_call_vs2
set a, 1 ; Return is expected
set pc, op_call_helper ; Works even with the long-form ones.


; Basically no games support this, so just no-op it.
:op_sound_effect
set pc, pop

; TODO Support time and routine parameters here.
; The first arg is always 1, and not meaningful.)
:op_read_char ; (1, time, routine)
jsr await_any_key ; A is now the key code.
; TODO Adjust from DCPU to Z-machine encoding.
set pc, zstore


; This one both stores and branches.
:op_scan_table ; (target, table, entries, format)
set push, x
set push, y
set push, z
set push, i
set push, j

ifl [var_count], 4
  set [var_args+3], 0x82 ; Default format.

set x, [var_args]   ; Target
set y, [var_args+1] ; Current address.
set z, [var_args+2] ; Table size in words.
shl z, 1 ; Convert to a byte size.
add z, y            ; Z now actually the top address.

set i, rwba
ifc [var_args+3], 0x80
  set i, rbba      ; I is now the function to call.

set j, [var_args+3]
and j, 0x7f         ; J is now the entry size in bytes.

; Now all the parameters are consistent, so let's begin looping.
set pc, L3011
:L3010
set a, y
jsr i ; A contains the read word or byte.
ife a, x
  set pc, L3012  ; Success, jump out.
; Otherwise, advance to the next one.
add y, j
:L3011
ifl y, z
  set pc, L3010
set y, 0 ; Error case. We reach the end without finding the target.
; Fall through to L3012, the finished case.
:L3012
set a, y ; Either the successful address, or 0 for failure.
jsr zstore
set a, y
jsr zbranch

set j, pop
set i, pop
set z, pop
set y, pop
set x, pop


:op_not
set a, [var_args]
xor a, -1
set pc, zstore

:op_call_vn
set a, 0 ; Return not expected.
set pc, op_call_helper

:op_call_vn2
set a, 0 ; Return not expected.
set pc, op_call_helper



; TODO Implement these
:op_tokenise
:op_encode_text

:op_copy_table ; (src, dest, size)
set push, x
set a, [var_args]
set b, [var_args]
set c, [var_args]

; If dest is 0, 0 out that many bytes of src.
ife b, 0
  set pc, L3020

; Choose the direction based on the addresses.
set x, zmove ; Forward, safe when src > dest
ifl a, b ; But when src < dest
  set x, zmove_rev
jsr x
set pc, L3021

:L3020 ; Zeroing-out.
set x, a
set push, y
set y, c

:L3022
ife y, 0
  set pc, L3023
set a, x
set b, 0
jsr wbba
add x, 1
sub y, 1
set pc, L3022

:L3023 ; Done the zeroing loop.
set y, pop
; Fall through to L3021.

:L3021
set x, pop
set pc, pop

:op_print_table ; TODO Implement me.

:op_check_arg_count ; (count)
set a, [zfp] ; Read the zfp
set a, [a + index_arg_count] ; And get the arg count for this routine.
set b, [var_args]
sub b, 1 ; Now it's numbered from 0.

set c, 0
ifl b, a ; If the requested arg was provided.
  set c, 1
set a, c
set pc, zbranch


