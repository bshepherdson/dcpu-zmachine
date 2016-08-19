
; Random number generator for the Z-machine.
:multiplier DAT 0x41c6, 0x4e6d
.def increment, 12345
.def modmask_hi, 0x7fff
.def modmask_lo, 0xffff

:previous_random DAT 0, 0

:seed ; (lo, hi) -> void
and a, modmask_lo
and b, modmask_hi
set [previous_random], b
set [previous_random+1], a
set pc, pop

; TODO: Seed from time after adding the clock hardware.
; TODO: Initialize this by calling seed() from the init flow.

; Returns a number in the full integer range.
:genrandom ; () -> u
set a, [previous_random]
set b, [previous_random+1]
mul b, [multiplier+1]
set c, ex
mul a, [multiplier]
add a, c
add b, increment
add a, ex
and a, 0x7fff
set [previous_random], a
set [previous_random+1], b
set a, b
set pc, pop

; Produces a random number 1 <= x <= n
:random ; (n) -> n
set push, a
jsr genrandom
mod a, pop
add a, 1
set pc, pop

