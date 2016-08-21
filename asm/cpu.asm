; Core CPU processing parts.
; Decoding instructions and the like.



:interp ; () -> void
set push, x
jsr rbpc
set x, a ; X = opcode

shr a, 6
and a, 3 ; Just the top 2 bits.
ife a, 3
  set pc, interp_variable
ife a, 2
  set pc, interp_short
ife x, 190
  ifg [version], 4
    set pc, interp_extended

:interp_long
; Operand count in long form is always 2OP.
; Bit 6 gives the type of the first operand, bit 5 the second.
set a, 1 ; Defaults to small constant $$01
ifb x, 0x40
  set a, 2 ; Bit set means variable, $$02
jsr read_arg
set push, a ; Save the argument value.
set a, 1
ifb x, 0x20
  set a, 2 ; Bit set means variable, $$02
jsr read_arg
set b, a
set a, pop ; Now we're ready to call the long-form operand.
and x, 31  ; Opcode is bottom 5 bits.
set c, [x+ops_2op]
set x, pop ; Restored the stack.
set pc, c  ; Now I can tail-call.


:interp_short
; Operand count is 1OP or 0OP, depending on the argument type in bits 4 and 5.
set a, x
shr a, 4
and a, 3
ife a, 3 ; 3 = no argument.
  set pc, interp_short_0op

:interp_short_1op
jsr read_arg ; A = argument
set c, x
and c, 15
set x, pop  ; Stack restored.
set pc, [c + ops_1op] ; Tail call.

:interp_short_0op
set c, x
and c, 15
set x, pop
set pc, [c + ops_0op]


:interp_variable
ifb x, 0x20
  set pc, interp_variable_2op


:interp_VAR
; VAR has a following byte for the argument types.
set [var_count], 0
jsr rbpc ; Read the type byte into A.
and x, 31 ; Opcode is bottom 5 bits.

; Special case: the double-var opcodes call_vs2 (12) and call_vn2 (26)
ife x, 12
  set pc, L4030
ife x, 26
  set pc, L4030

set pc, L4031

:L4030 ; Handle the double-var opcodes.
set push, a ; Save the first type byte.
jsr rbpc ; Read the second one.
set b, pop
set push, a ; Swap them, saving the second one to the stack.
set a, b
jsr consume_var_arg_byte ; Read the first byte.

set a, pop ; And load A with the second one, to be loaded below.
; Fall through to L4031 below.

:L4031
jsr consume_var_arg_byte ; Bytes are filled in, no return value.

; Either way, carry on now.
set c, x
set x, pop
set pc, [c + ops_var]


; Variable-form 2OP instructions.
:interp_variable_2op
set [var_count], 0
jsr rbpc ; A = arg byte
jsr consume_var_arg_byte
; Now the opcode is in the bottom 5 bits.
set c, x
and c, 31
set a, [var_args]
set b, [var_args+1]
set x, pop
set pc, [c + ops_2op]


:interp_extended
jsr rbpc
set x, a
; Now it's the same as variable form.
set [var_count], 0
jsr rbpc ; A is now the arg type byte
jsr consume_var_arg_byte
set c, x
set x, pop
set pc, [c + ops_extended]



:var_args
DAT 0, 0, 0, 0, 0, 0, 0, 0
:var_count DAT 0

:read_var_arg ; (type) -> void
jsr read_arg
set b, [var_count]
set [b + var_args], a
add b, 1
set [var_count], b
set pc, pop

:consume_var_arg_byte ; (type byte)
set push, y
set y, a ; Y is now the type byte
shr a, 6
ife a, 3
  set pc, L40
jsr read_var_arg
set a, y
shr a, 4
and a, 3
ife a, 3
  set pc, L40
jsr read_var_arg
set a, y
shr a, 2
and a, 3
ife a, 3
  set pc, L40
jsr read_var_arg
set a, y
and a, 3
ife a, 3
  set pc, L40
jsr read_var_arg

:L40
set y, pop
set pc, pop


; 0 is large constant, 1 is small. 2 is variable (by value), 3 is omitted.
; No need to wrap the first two: they're just rbpc and rwpc.
:arg_types DAT rwpc, rbpc, read_arg_type_variable

:read_arg
; Handle this error somehow, it's a good sanity check.
; ife a, 3
; hcf 0 ; Fail if we ever get passed a 3.
set pc, [a + arg_types]

:read_arg_type_variable ; () -> value
jsr rbpc ; A = variable number
set pc, read_variable

:read_variable ; (var) -> value
ife a, 0
  set pc, zpop ; Tail-call to popping the stack.
ifg a, 16
  set pc, read_global
; Fall through to read_local

; Reads a 1-based local variable.
; See below for the stack diagram.
:read_local ; (var) -> value
jsr local_address
set a, [a]
set pc, pop



; Turns a 1-based local number into a native DCPU address.
:local_address ; (number) -> real_address
set b, [zfp]
add b, a
set pc, pop


; Turns a 16-based global variable number into a Z-machine byte address.
:global_address ; (number) -> ba
sub a, 16 ; Offset into the table.
shl a, 1  ; Convert the number to a word offset.
set push, a
set a, header_globals
jsr rwba
add a, pop
set pc, pop


; Global variables exist at a table in memory.
:read_global
jsr global_address
set pc, rwba ; Tail call to read that address.



:zstore ; (value) -> void
set push, a
jsr rbpc ; A = storage target
set b, pop
set pc, write_variable


:write_variable ; (var, value) -> void
ife a, 0
  set pc, write_stack
ifg a, 16
  set pc, write_global
; Fall through the write_local
:write_local ; (var, value) -> void
; Expects a 1-based local number.
set push, b
jsr local_address
set [a], pop
set pc, pop

:write_global ; (var, value) -> void
; Expects the 16-based global number.
set push, b
jsr global_address
set b, pop
set pc, wwba ; Tail call

:write_stack ; (var, value) -> void
set a, b
set pc, zpush ; Tail call


:zbranch ; (cond) -> void
ifn a, 0
  set a, 0xffff
set push, a ; Push the condition for now.
jsr rbpc ; A is now the first byte of the branch offset.
; Determine if we're doing the skipping.
; We xor the top bit with the condition - if they match (0) we jump.
set c, a
and c, 0x80
xor peek, c ; TOS is the jump flag. If it's 0, branch. NB: inverted!

ifb a, 0x40
  set pc, L50

; Long form (remember signed)
jsr rbpc
set b, pop
shl b, 8
bor a, b
and a, 0x3fff ; Mask off the top two bits.
ifb a, 0x2000 ; Convert 14-bit signed to 16-bit signed.
  bor a, 0xc000 ; If bit 13 is set, set the top two as well.
set pc, L51

:L50 ; Short form (bottom 6 bits)
set a, pop
and a, 0x63

:L51 ; Actual code
; First, two special cases. 0 means return false, 1 means return true.
ifc a, 0xfffe ; Only bit 1 is set, if any.
  set pc, L52

; Main case: PC = PC + offset - 2
; Can't handle 2s complement properly here.
sub a, 2
set pc, branch_signed ; Tail call.

; Return false or true; A holds 0 or 1.
:L52
jsr zreturn
set pc, pop

; A is a 16-bit signed offset to apply to the PC.
; This logic is tricky, and its used in zbranch and elsewhere, so it gets a
; function.
:branch_signed ; (signed_delta) -> void
ifu a, 0
  set pc, L55

; Positive case
add [zpc+1], a
add [zpc], ex
set pc, L56

; Negative case
:L55
xor a, -1
add a, 1 ; Negate A to produce the positive equivalent.
sub [zpc+1], a
add [zpc], ex  ; Yes, add. EX is -1 when there's a borrow.
; Fall through to L56 for return.

:L56
set pc, pop




; Stack for a routine looks like this:
; Routines use a frame pointer in C fashion.
; When we start a new routine, the stack looks like this:
; old stack ...
; ------------
; local N
; ....
; local 1
; old-fp           <--- fp
; old-sp
; old-pc-lo
; old-pc-hi
; arg-count
; return-expected  <--- sp

; When a return is expected, the old PC actually points to the Store target at
; the end of the opcode. So after restoring everything, we can use zstore.

; Offsets from FP to the various values.
.def index_old_fp, 0
.def index_old_sp, -1
.def index_old_pc_lo, -2
.def index_old_pc_hi, -3
.def index_arg_count, -4
.def index_return_expected, -5

:zreturn ; (value) -> void
set b, [zfp]
set c, [b + index_return_expected] ; Hang onto the return-expected flag.
set [zpc+1], [b + index_old_pc_lo] ; Restore PC
set [zpc], [b + index_old_pc_hi]
set [zsp], [b + index_old_sp]
set [zfp], [b + index_old_fp]

ifn c, 0      ; Store when the should-return flag (C) is nonzero.
  jsr zstore
set pc, pop



; Copies C words from A to B, forward.
:move ; (from, to, len) -> void
ife c, 0
  set pc, pop
set [b], [a]
add a, 1
add b, 1
sub c, 1
set pc, move

; Works with byte addresses, copying bytes. Copies forward.
:zmove ; (from, to, len) -> void
set push, x
set push, y
set push, z
set x, a
set y, b
set z, c

:L80
ife z, 0
  set pc, L81
set a, x
jsr rbba
set b, a
set a, y
jsr wbba
add x, 1
add y, 1
sub z, 1
set pc, L80

:L81
set z, pop
set y, pop
set x, pop
set pc, pop


; Works with byte addresses, copying bytes. Copies backward.
:zmove_rev ; (from, to, len) -> void
set push, x
set push, y
set push, z
set x, a
add x, c
set y, b
add y, c
set z, c

; Now the addresses are 1 higher than they should be, so subtract first.
:L90
ife z, 0
  set pc, L91
sub x, 1
sub y, 1
sub z, 1
set a, x
jsr rbba
set b, a
set a, y
jsr wbba
set pc, L90

:L91
set z, pop
set y, pop
set x, pop
set pc, pop


; Major function, responsible for calling routines.
; It expects the arguments to be in an array, with a given length.
; This is a long call, it uses X to store the argument array, Y return-expected
:zcall ; (routine_hi, routine_lo, arg_count, arg_array, return-expected)
ife a, 0
  ife b, 0
    set pc, L70 ; Special case for calling 0 = instant return.
; Main case
set push, i
set push, j
set i, [zpc]    ; Save the old PC.
set j, [zpc+1]
set [zpc], a
set [zpc+1], b  ; And set it to the new one.

; Now we can use rbpc to read the local count byte.
set push, c
jsr rbpc   ; A = local count.
set b, [zsp]
sub b, a   ; Make room for A locals plus 1
sub b, 1
; B now points at the old-fp location, so store that.
set [b], [zfp]
set [zfp], b

; Let's store the old values while we've got B = FP
set [b + index_old_sp], [zsp]
set [b + index_old_pc_lo], j
set [b + index_old_pc_lo], i
set [b + index_return_expected], y
set y, pop    ; Use Y for the argument count now.
set [b + index_arg_count], y

sub b, 5   ; SP is 5 cells farther down.
set [zsp], b

; Now in versions below 5, we need to copy the default locals.
; In versions 5+, we need to 0 the locals.
; A is the local count, Y the argument count.
set j, a ; Local count in J.
set i, 1 ; Local number 1.
:L71
ifg i, j
  set pc, L72
set a, 0
ifl [version], 5
  jsr rwpc       ; A is now the correct value, either way.
set b, a
set a, i
jsr write_local  ; (var, value)
add i, 1
set pc, L71

:L72
; Now copy the arguments over top of the locals.
set c, j  ; Local count
ifl y, j  ; If arg count is less
  set c, y ; C is now min(#args, #locals)
set a, x   ; A, the source, is the provided args array.
set b, [zfp]
add b, 1   ; B, the destination, is the region of the stack.
jsr move

; Everything should now be good: locals are set up, stack pointers are good.
set j, pop
set i, pop
set pc, pop


:L70 ; Called 0, return instantly.
set a, 0
jsr zstore
set pc, pop


:msg_illegal_opcode .asciiz "[Illegal opcode]"

:unrecognized_opcode
set a, msg_illegal_opcode
set pc, emit_native_string


; Called on startup, or if the Z-machine is ordered to restart.
; Needs to (re)load the dynamic memory, set the header accordingly, etc.
; Never returns! It loops over interp forever.
:zrestart
; Load the dynamic and static memory regions at memory_base.
jsr load_low_mem
; Set the version
set a, header_version
jsr rbba
set [version], a

jsr zrestart_flags1
jsr zrestart_flags2
jsr zrestart_interpreter_details
jsr zrestart_screen_details
jsr zrestart_colours
jsr zrestart_standard_number

:L4020
jsr interp
set pc, L4020

:zrestart_flags1
; Need to set up the header flags and fields.
set a, header_flags1
jsr rbba ; A is Flags 1

ifg [version], 4
  set pc, L190

; v1-3: we set bits 4-6.
; 4: Status line NOT available
; 5: Screen-splitting available.
; 6: Variable-pitch font by default
; So we're setting them to 1, 0 and 0
and a, 0x8f
bor a, 0x10
set b, a
set a, header_flags1
jsr wbba
set pc, L191

:L190 ; v4+ Flags 1
; None of these special features are available - set it to 0.
set b, 0
set a, header_flags1
jsr wbba
; Fall through to L191

:L191
set pc, pop


:zrestart_flags2
; Game might set bits 3-8; None of which are supported. Set them all off.
set a, header_flags2
jsr rwba
set b, a
and b, 0x07 ; Preserve only the lower 3 bits.
set a, header_flags2
jsr wwba
set pc, pop

:zrestart_interpreter_details
set a, header_interpreter_number
set b, 6
jsr wbba
set a, header_interpreter_version
set b, 65
jsr wbba
set pc, pop

:zrestart_screen_details
set a, header_screen_height_lines
set b, screen_rows
jsr wbba
set a, header_screen_width_chars
set b, screen_cols
jsr wbba
set a, header_screen_width_units
set b, screen_cols
jsr wwba
set a, header_screen_height_units
set b, screen_rows
jsr wwba
set a, header_font_width_units
set b, 1
jsr wbba
set a, header_font_height_units
set b, 1
jsr wbba
set pc, pop

:zrestart_colours
set a, header_default_fg_colour
set b, 9 ; white
jsr wbba
set a, header_default_bg_colour
set b, 2 ; black
jsr wbba
set pc, pop

:zrestart_standard_number
set a, header_standard_revision
set b, 0
jsr wwba
set pc, pop


; Loads the first sector of memory at memory_base, then determines how many
; more to load and loads those too.
:load_low_mem ; () -> void
set push, x
set push, y
set push, z
set a, 2    ; READ
set x, 0
set y, memory_base
hwi [hw_disk]
jsr await_disk_ready

; Now I can read the base of hi memory.
; header_himem happens to be word-sized and even, fortunately.
set z, header_himem
shr z, 1
add z, memory_base
set z, [z]
; Round that up to a full sector (in bytes).
add z, 1023
; And then truncate to a number of sectors, not bytes.
shr z, 10

; The first is already loaded, so we set X to 1.
set x, 1
:L202
set a, 2    ; READ
add y, sector_size
hwi [hw_disk]
jsr await_disk_ready

add x, 1
ife x, z ; We've read the last sector.
  set pc, L203
set pc, L202

:L203 ; Done loading sectors.
set z, pop
set y, pop
set x, pop
set pc, pop

