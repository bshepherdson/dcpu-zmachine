; Encapsulating the tricky memory access parameters.

.def memory_base, 0x8000

; Holds the size of the dynamic memory region.
; Addresses less than this are loaded directly to DCPU memory.
; Higher addresses are in the upper region.
:memory_top DAT 0

; These are the cooked access words, intended for calling from the rest of the
; system.
:rbba ; ( ba -- b )
set b, a
shr b, 1
set b, [b + memory_base]
ifc a, 1
  shr b, 8 ; If bit 0 is clear, this is the high byte, so shift it down.
and b, 255
set a, b
set pc, pop

; As an optimization, when bit 0 is clear we can read directly.
:rwba ; ( ba -- w )
ifc a, 1
  set pc, rwba_direct

; Read the high byte
set push, x
set push, y
set x, a
jsr rbba ; A = high byte
shl a, 8
set y, a
set a, x
add a, 1
jsr rbba ; A = low byte
bor y, a
set a, y
set y, pop
set x, pop
set pc, pop

:rwba_direct
shr a, 1
set a, [a+memory_base]
set pc, pop


:wbba ; ( ba b -- )
set push, x
set push, y
set x, a
shr x, 1
set c, [x+memory_base]
set y, 255
ifb a, 1   ; When even/high byte,
  shl y, 8 ; Shift the mask up
and c, y   ; Mask out the part I'm replacing.
ifc a, 1   ; When high byte,
  shl b, 8 ; Shift the value up.
bor b, c
set [x+memory_base], b
set y, pop
set x, pop
set pc, pop

:wwba ; ( ba w -- )
; Write directly when the address is even.
ifc a, 1
  set pc, wwba_direct

; Otherwise, write twice.
set push, a ; Address on bottom
set push, b ; Value on top
shr b, 8
JSR wbba
set b, pop
and b, 255
set a, pop
add a, 1
jsr wbba
set pc, pop

:wwba_direct
shr a, 1
set [a+memory_base], b
set pc, pop



; Now adding the complex disk caching scheme.
; With 512 words per sector, each one is 0x200 long, so 8 is 0x1000.
; I'll guess I can get away with 0x2000 = 16 sectors of cache.

; A 32-bit long address specifies a byte in the final file. To turn that into a
; sector number and DCPU word address, it looks like this:
; 01234567 89abcdef 01234567 89abcdef
; 00000000 0000ssss ssssssoo ooooooo_
; which is 10 bits of sector and 9 of word.

; To actually split it up, I'll shift the upper word up by 6, shift the lower
; down by 10, and BOR them together for the sector number.
; Shifting right by 1 and AND 0x1ff gives the offset.

.def cache_count, 16
.def sector_size, 512
.def sector_shift, 9
.def cache_base, 0x6000

:cache_sectors
DAT -1, -1, -1, -1, -1, -1, -1, -1
DAT -1, -1, -1, -1, -1, -1, -1, -1

:cache_next_eviction DAT 0

; They're filled in a round-robin style, which is thrash-proof, though not
; optimal in general.
; Offset is the DCPU word we're after!
; 49, 1c6
:read_sector ; (sector, offset) -> word
set c, 0
:L10
ife a, [c+cache_sectors]
  set pc, L11
add c, 1
ife c, 16
  set pc, L12
set pc, L10

:L12 ; Failed to find it, so read it into the new location.
set push, x
set push, y
set push, b ; Save the offset.
set c, [cache_next_eviction]
set [c+cache_sectors], a
set y, c   ; Set aside the index for below.
add c, 1
and c, 15
set [cache_next_eviction], c

set x, a
shl y, sector_shift
add y, cache_base ; Y is now the target address.
set push, y       ; Save the address.
set a, 2 ; READ
hwi [hw_disk]
jsr await_disk_ready

; Now the sector is loaded, it's properly indexed from the table.
; Just need to look up the word.
set x, pop ; Base address
add x, pop ; Offset
set a, [x] ; Loaded the word
set y, pop ; Restore the original Y
set x, pop ; Restore the original X
set pc, pop

:L11 ; Found the target sector - C is its number.
shl c, sector_shift
add c, cache_base
add c, b
set a, [c]
set pc, pop



; Read a byte from a long address.
:rbla ; (hi, lo) -> byte
ife a, 0
  ifl b, [memory_top]
    set pc, L20

; Need to do the full range.
; Convert to the (sector, DCPU word offset) arguments for read_sector.
set push, b
shr b, sector_shift + 1
shl a, 6
bor a, b
set b, peek
shr b, 1
and b, 511 ; Make sure it's just the offset portion.
jsr read_sector
set b, pop
ifc b, 1
  shr a, 8 ; If this is the high byte, shift it down.
and a, 255
set pc, pop

:L20
set a, b
set pc, rbba ; Tail call to rbba



; Read a word from a long address.
:rwla ; (hi, lo) -> byte
ife a, 0
  ifl b, [memory_top]
    set pc, L30

; Odd addresses get double-called.
ifb b, 1
  set pc, L31

; Need to do the full range.
; Convert to the (sector, DCPU word offset) arguments for read_sector.
set push, b
shr b, 10
shl a, 6
bor a, b
set b, pop
shr b, 1
and b, 511 ; Make sure it's just the offset portion.
jsr read_sector
set pc, pop

:L31
; Crossing a boundary, so making two calls against rbla() above.
set push, x
set push, a
set push, b
jsr rbla
set x, a ; Save the byte.
shl x, 8 ; Shift it up.
set b, pop
set a, pop
add b, 1
jsr rbla
bor a, x
set x, pop
set pc, pop

:L30
set a, b
set pc, rwba ; Tail call



; Converts a packed address to a two-word long address.
; V1-3 = 2x, V4-5 = 4x, V8 = 8x
:pa_la ; (pa) -> (hi, lo)
set b, 1
set c, [version]
ifg c, 3
  shl b, 1
ifg c, 5
  shl b, 1
shl a, b
set b, a
set a, ex
set pc, pop

; Converts a word address (only used in the abbreviations table) to a long
; address.
:wa_la ; (wa) -> (hi, lo)
set b, a
shl b, 1
set a, ex
set pc, pop


:rbpc_peek ; () -> byte
set a, [zpc]
set b, [zpc+1]
set pc, rbla ; Tail call

:pc_bump ; (delta) -> void
add [zpc+1], a
add [zpc], ex
set pc, pop

; Bumps PC after reading.
:rbpc ; () -> byte
jsr rbpc_peek
set push, a
set a, 1
jsr pc_bump
set a, pop
set pc, pop

:rwpc ; () -> word
set a, [zpc]
set b, [zpc+1]
jsr rwla
set push, a
set a, 2
jsr pc_bump
set a, pop
set pc, pop


