; Library functions for working with Z-machine objects.

; These are configured for v3 and below by default.
:zobj_offset_parent  dat 4
:zobj_offset_sibling dat 5
:zobj_offset_child   dat 6
:zobj_offset_props   dat 7
:zobj_defaults_table_size dat 62 ; 31 words
:zobj_entry_size     dat 9

; Based on the version, configures the various version-dependent properties.
:init_object_system ; () -> void
ifl [version], 4
  set pc, pop
set [zobj_offset_parent], 6
set [zobj_offset_sibling], 8
set [zobj_offset_child], 10
set [zobj_offset_props], 12
set [zobj_defaults_table_size], 126 ; 63 words
set [zobj_entry_size], 14
set pc, pop


; The table begins with the property defaults table.
:object_table_base ; () -> ba_of_object_table
set a, header_obj_table
set pc, rwba ; A is now the table base address.

:zobject_0
jsr object_table_base
add a, [zobj_defaults_table_size]
set pc, pop

:zobj_addr ; (obj_num) -> ba of object entry
sub a, 1 ; There's no object 0
mul a, [zobj_entry_size]
set push, a
jsr zobject_0
add a, pop ; A is now the address of our object.
set pc, pop


:zobj_read_relative ; (obj_addr, offset) -> obj_num_of_relative
add a, b
set c, rbba
ifg [version], 3
  set c, rwba
jsr c
set pc, pop

:zobj_write_relative ; (obj_addr, offset, num) -> void
add a, b ; A is the byte address.
set b, c ; B is the target value.
set c, wbba
ifg [version], 3
  set c, wwba   ; C is now the required function.
jsr c
set pc, pop



; Works backwards from the address of a property's data to its whole entry
; address.
; In versions 1-3, the size is always one byte, so we just subtract one.
:zobj_prop_data_to_prop
sub a, 1
ifl [version], 4
  set pc, pop ; In v1-3 subtracting 1 byte is always sufficient.

; v4+, tricky case. The size is either 1 or 2 bytes, depending.
; A two-byte size has the top bit set in both bytes. A one-byte entry has the
; top bit clear.
set push, a
jsr rbba
set b, a ; B is now the value of the nearest size byte.
set a, pop
ifb b, 0x80 ; If the top bit is set, we need another byte.
  sub a, 1
; Now A is the correct address for the start of the entry, either way.
set pc, pop


; The size of the property is:
; - v1-3: size byte shifted down by 5, plus 1.
; - v4+ with top bit set: the second byte has the length in its lower 6 bits
;   (0 = 64)
; - v4+ with top bit clear: bit 6 clear = 1, set = 2.
:zobj_prop_size ; (address of property entry) -> size in bytes
ifl [version], 4
  set pc, L300

; v4+: read the byte and check its top bit.
set push, a
jsr rbba ; A is now the byte.
ifb a, 0x80 ; If its top bit is set, the two-byte case.
  set pc, L301
; If not, the one-byte case: just examine bit 6.
set b, pop
set b, a ; B is the byte
set a, 1
ifb b, 0x40
  set a, 2 ; If bit 6 of B is set, length is 2.
set pc, pop

:L301 ; Two-byte case.
set a, pop
add a, 1
jsr rbba ; A is now the second byte.
and a, 0x3f ; Lower 6 bits only.
ife a, 0
  set a, 64 ; Special case 0 to be 64.
set pc, pop

:L300 ; v1-3 case
jsr rbba ; A is the byte itself.
shr a, 5 ; Shift it right. Now we have a 3-bit length field.
add a, 1 ; Add 1, so we have a range 1-8, not 0-7.
set pc, pop


; Takes an object number, and removes this object from its parent, if any.
; Repairs the sibling list.
; The moving object retains its children, if any.
:zobj_remove ; (obj_num) -> void
; First, check if the parent is already 0; there's nothing to do if so.
set push, a ; Save my object number.
jsr zobj_addr
set push, a ; And my address.
set b, [zobj_offset_parent]
jsr zobj_read_relative ; A is now the parent number.
ife a, 0
  set pc, L310 ; Just return (includes popping the saved address).

; Work to do. A is my parent's number.
jsr zobj_addr ; Now A is the parent's address.
; Two cases: Target object is either the immediate child of the parent, or a
; sibling of some other child.
set push, a
set b, [zobj_offset_child]
jsr zobj_read_relative ; A is now the child's number.
ife a, [sp+2] ; Stack is now ( ... number address parent_address )
  set pc, L311 ; I'm the direct child

; Not the direct child, rather a sibling.
; A is the child's number.
; Pop the now-unnecessary parent's address off the stack.
set b, pop ; Stack is now ( ... number address )
jsr zobj_addr ; A is now the immediate child's address.

; Now we begin a loop that's looking for the object whose sibling is the target.
:L312
set push, a ; Save the current child's address.
set b, [zobj_offset_sibling]
jsr zobj_read_relative ; A is the sibling's number.
ife a, [sp+2] ; Stack is ( ... number address cur-sibling-addr )
  set pc, L313 ; Found our goal.
; If we're still here, we advance to the sibling and loop.
jsr zobj_addr ; A is now the next sibling's address.
set b, pop    ; And we discard the old address off the stack.
set pc, L312

:L313 ; When we get down here, the immediately-previous sibling is on the stack.
; Grab the target object's sibling number.
set a, [sp+1] ; Stack is ( ... number address sibling-address )
set b, [zobj_offset_sibling]
jsr zobj_read_relative ; A is now the sibling number of the target.

set c, a   ; Move that to C.
set a, pop ; A is now the previous sibling's address.
set b, [zobj_offset_sibling]
jsr zobj_write_relative ; So we set the sibling of the previous to the next.
; That removes myself from the chain.
; Jump to the common last step.
set pc, L314


; Case 2: I'm the direct child of my parent. Stack ( ... num addr parent-addr )
:L311
; Read my sibling field, write it as the child of my parent.
set a, [sp+1] ; A is my address.
set b, [zobj_offset_sibling]
jsr zobj_read_relative ; A is now the sibling number.
set c, a ; Move it to C
set a, pop ; Pop my parent address to A
set b, [zobj_offset_parent]
jsr zobj_write_relative ; And write the target's sibling as the parent's child.
; Now we have ( ... num addr ) and can move to the common last step.
; Fall through to L314 below.

:L314 ; At this point, we have ( ... number address ) and I've been removed
; from my own parent.
; I need to actually set my parent and sibling to 0.
set a, peek
set b, [zobj_offset_parent]
set c, 0
jsr zobj_write_relative
set a, peek
set b, [zobj_offset_sibling]
set c, 0
jsr zobj_write_relative
; Fall through to L310 below for cleanup.

:L310 ; Removing the saved number and address from the stack, and returning.
set a, pop
set a, pop
set pc, pop




; Moves the target object (A) to be the first child of B.
; Remove A from its own parent first, if any.
; If A is already a child of B, it becomes the first child.
:zobj_insert_child ; (target, destination) -> void
set push, a
set push, b
jsr zobj_remove ; Remove the target from its own parent, first.
set a, peek ; A is the destination's number.
jsr zobj_addr ; Now its address.
set push, a ; Push that too. ( ... target dest dest_addr )

; Now we read the child of the destination, set it to the target's sibling.
set b, [zobj_offset_child]
jsr zobj_read_relative ; A is now the child of the destination.
set push, a ; ( ... target dest dest_addr child )

set a, [sp+3] ; A = target number
jsr zobj_addr ; A = target address
set push, a   ; Save that ( ... target dest dest_addr child target_addr )

; First, set the parent of the target to be the destination.
set b, [zobj_offset_parent]
set c, [sp+3] ; C = destination number
jsr zobj_write_relative
; Then the sibling of the target to be the saved child.
set a, pop
set c, pop ; ( ... target dest dest_addr )
set b, [zobj_offset_sibling]
jsr zobj_write_relative

; And finally the child of the destination to the target.
; ( ... target dest dest_addr )
set a, pop
set b, pop ; Discard the destination number, we're done with it.
set b, [zobj_offset_child]
set c, pop ; C is the target number.
jsr zobj_write_relative
; Stack is clean, and all good.
set pc, pop



; An object's property table begins with a byte giving the length in Z-machine
; words of its short name, then that many words of short name, then the
; properties themselves.
; Returns a BYTE ADDRESS for the object's short name.
:zobj_short_name ; (zobj-addr) -> (ba_name)
; First, get the address for the object's property table.
add a, [zobj_offset_props]
jsr rwba ; A is now the byte address of the property table/the length byte.
add a, 1 ; Skip over the length byte.
set pc, pop


; Returns a mask for the given attribute.
:zobj_attr_mask ; (attr) -> mask
and a, 7
set b, 0x80
shr b, a
set a, b
set pc, pop


; Returns the BYTE ADDRESS for the byte containing the given attr.
:zobj_attr_byte ; (obj_num, attr) -> ba
set push, b
jsr zobj_addr
set b, pop
shr b, 3 ; B is now an offset in bytes, rather than the bit number.
add a, b
set pc, pop

:zobj_set_attr ; (obj_num, attr) -> void
set push, x
set push, y
set push, b
jsr zobj_attr_byte ; A is now the byte address for the byte.
set x, a
set a, pop ; Grab the attr number again.
jsr zobj_attr_mask ; A is now the mask.
set y, a  ; And Y is the mask.

set a, x
jsr rbba ; Read the byte.
bor a, y ; OR in the mask
set b, a
set a, x
jsr wbba ; And write it back.

set y, pop
set x, pop
set pc, pop

:zobj_clear_attr ; (obj_num, attr) -> void
set push, x
set push, y
set push, b
jsr zobj_attr_byte ; A is now the byte address for the byte.
set x, a
set a, pop ; Grab the attr number again.
jsr zobj_attr_mask ; A is now the mask.
xor a, -1 ; Invert the mask.
set y, a  ; And Y is the mask.

set a, x
jsr rbba ; Read the byte.
and a, y ; AND in the mask
set b, a
set a, x
jsr wbba ; And write it back.

set y, pop
set x, pop
set pc, pop


:zobj_test_attr ; (obj_num, attr) -> set?
set push, b
jsr zobj_attr_byte ; A is now the byte address.
jsr rbba ; A is now the byte in question.
set b, pop
set push, a
set a, b    ; Save the byte and put the attr number into A
jsr zobj_attr_mask ; A is now the mask.
set c, 0
ifb a, pop
  set c, 1
set a, c
set pc, pop


:zobj_first_prop ; (obj_addr) -> ba_for_first_property_entry
add a, [zobj_offset_props]
jsr rwba ; Address of the object's property table.
; That starts with a byte giving the length of the short name in words.
set push, a
jsr rbba ; A is now the number of 2-byte words I need to move it by.
shl a, 1 ; Byte offset.
add a, 1 ; 1 more for the length byte itself.
add a, pop ; A is now the address of the first entry.
set pc, pop


; Returns the byte address for the requested property - or 0 if there is no
; value for it.
; DOES NOT understand property defaults.
; The returned address is aimed at the whole entry, not just the property data.
:zobj_get_prop ; (obj_addr, prop_num) -> prop_ba
set push, x
set push, z
set z, b ; Save the prop number in Z
jsr zobj_first_prop ; A is now the address of the first property.
set x, a ; And keep the current property entry in X.

:L320
set a, x
jsr zobj_prop_num ; A is the property number for this entry. 0 for none/end.
ife a, z
  set pc, L322 ; If we've found the target property, we're done.
ife a, 0
  set pc, L321 ; Bail, there's no more properties.

; Otherwise, advance to the next one.
set a, x
jsr zobj_next_prop
set x, a
set pc, L320


:L322 ; Success: found the target property. It's address is in X.
set a, x
set pc, L323

:L321 ; Failure, ran out of properties without finding it.
set a, 0
; Fall through to L323

:L323
set z, pop
set x, pop
set pc, pop



; Retrieves the property number for this property.
; Two cases: in v1-3 it's the low 5 bits of the first byte, in v4+ the low 6.
:zobj_prop_num ; (ba_prop_entry) -> prop_num
jsr rbba ; Read the (first) size byte.
set b, 0x1f ; Low 5 bits.
ifg [version], 3
  bor b, 0x20 ; Add the extra bit.
and a, b
set pc, pop

; Takes a pointer to a prop entry, and returns the pointer to its data.
:zobj_prop_data ; (ba_prop_entry) -> ba_prop_data
set push, a
jsr rbba ; Read the first byte.
set c, 1
ifg [version], 3 ; If v4+ and
  ifb a, 0x80 ; The top bit is set
    set c, 2 ; Then it's a 2-byte size header.
set a, pop
add a, c ; A should now be the data address.
set pc, pop


:zobj_next_prop ; (ba_prop_entry) -> ba_prop_entry
; Needs to compute the size of the property.
set push, x
set x, a
jsr zobj_prop_size ; A is the number of data bytes.
set push, a ; Save that size.

; If the version is < 4, it's always 1 byte.
set c, 1
ifl [version], 4
  set pc, L330

; In v4+, need to check the top bit.
set a, x
jsr rbba ; Read the first byte.
set c, 1 ; Default to 1.
ifb a, 0x80 ; If the top bit is set, it's 2
  set c, 2

:L330 ; C is the header size, X the address, and the data size is on the stack.
add x, c
add x, pop
set a, x    ; A is the return value now: the address of the next entry.
set x, pop
set pc, pop


