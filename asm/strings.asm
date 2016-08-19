; One important point for Z-machine strings is that we never actually need a
; decoded string in memory. We can simplify the flow by simply streaming the
; decoded characters to a function emit(c).

; There's essentially a stack of Z-string sources.
; Each one holds a long pointer for the next word.
; Z-chars are pulled on-demand from the strings by zstr_next() calls.
; It is responsible for working its way through each string, then popping the
; stack when each string is exhausted.

; Abbreviations are constrained to not use abbreviations recursively, or to end
; with incomplete multi-character constructions.

; We can actually just have some globals, including a depth, and push and pop
; the old globals as we move into and out of abbreviations.

:zstr_stack DAT 0, 0, 0, 0, 0, 0, 0, 0

; The set of globals that need saving:
:zstr_ptr dat 0, 0
:zstr_word dat 0
:zstr_index dat 0

; And this keeps track of the nesting depth.
:zstr_depth dat 0

; This doesn't need to be saved, since supposedly abbreviations don't end with
; incomplete multi-character segments.
:shift DAT 0

; Returns -1 when the string is exhausted.
:zstr_next ; () -> c
ife [zstr_index], 0
  set pc, L80

; Otherwise there are still characters to be had right here in this char.
set a, [zstr_word]
set b, [zstr_index]
sub b, 5
shr a, b
set [zstr_index], b
and a, 31
set pc, pop

:L80 ; We need to fetch the next character.
; First we check if this string is exhausted.
ifb [zstr_word], 0x8000
  set pc, L81

; We still have more characters.
; So read one and then bump the pointer.
set a, [zstr_ptr]
set b, [zstr_ptr+1]
jsr rwla ; A is now the word we read.
set [zstr_word], a
set [zstr_index], 15

add [zstr_ptr+1], 2
add [zstr_ptr], ex
set pc, zstr_next ; Things are reset now, so tail-recurse and it will return.

:L81 ; We've run out of string, so we need to pop the string.
; If the depth is nonzero, we pop the variables and recurse.
; If the depth is 0, we're all done with printing the string, so bail.
ife [zstr_depth], 0
  set pc, L82

; Otherwise popping is needed.
set a, [zstr_depth]
sub a, 1
shl a, 2   ; Turn the index (eg. 1, 2) into an offset (0, 4)
add a, zstr_stack

set [zstr_ptr], [a]
set [zstr_ptr+1], [a+1]
set [zstr_word], [a+2]
set [zstr_index], [a+3]
sub [zstr_depth], 1
set [shift], 0
set pc, zstr_next

:L82
set a, -1
set pc, pop



; Internals of printing. zstr_main is the hub function, it fetches a character,
; acts on it, and tail-recurses as needed.
:zstr_main ; () -> void
jsr zstr_next
ife a, -1
  set pc, pop

; Otherwise, let's examine our character.
; Special case: Character 6 in A2 is the longhand literal character.
ife a, 6
  ife [shift], 2
    set pc, zstr_longhand_literal

ifg a, 5
  set pc, zstr_basic_character

; If we're still here, it's something special.
set pc, [a + special_chars]



:zstr_longhand_literal ; () -> void
; Read the next two characters.
jsr zstr_next
shl a, 5
set push, a
jsr zstr_next
bor a, pop
; Convert it to a Z-machine character.
jsr emit
set [shift], 0
set pc, zstr_main ; Tail call back to the top.

:zstr_basic_character ; (c) -> void
sub a, 6
set b, [shift]
set b, [alphabets+b]
add b, a
set a, [b] ; Read the character for it.
jsr emit
set [shift], 0
set pc, zstr_main


:alphabets DAT alphabet0, alphabet1, alphabet2
:alphabet0 DAT "abcdefghijklmnopqrstuvwxyz"
:alphabet1 DAT "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
:alphabet2 DAT 0, 0x13, "0123456789.,!?_#'", 34, "/\\-:()"


; TODO If I care about V1 and 2, fix these.
:special_chars
DAT sc_space, sc_abbrev, sc_abbrev, sc_abbrev, sc_shift, sc_shift

:sc_space
set a, 32
jsr emit
set [shift], 0
set pc, zstr_main

:sc_shift ; A is 4 or 5
sub a, 3
set [shift], a
set pc, zstr_main

:sc_abbrev
sub a, 1
shl a, 5
set push, a ; abbreviation block
jsr zstr_next
add a, pop  ; that's the abbreviation number.
shl a, 1    ; Now it's an offset into the table.
set push, a
set a, header_abbreviations
jsr rwba    ; A is the address of the table.
add a, pop  ; Now of our particular target.
jsr rwba    ; Now the word address for the abbreviation.
jsr wa_la   ; A:B is now the long address.

; Push onto the stack.
set c, [zstr_depth]
shl c, 2
add c, zstr_stack
set [c],   [zstr_ptr]
set [c+1], [zstr_ptr+1]
set [c+2], [zstr_word]
set [c+3], [zstr_index]
add [zstr_depth], 1

; Load the new string into the variables.
set [zstr_ptr], a
set [zstr_ptr+1], b
set [zstr_index], 0
set [zstr_word], 0
set [shift], 0
set pc, zstr_main



; Now we have a series of functions that print an input Z-string.

:print_paddr ; (pa) -> void
jsr pa_la ; A:B is now the address.
set pc, print_la

; Prints from the current PC forward, advancing the PC to after the word.
:print_pc ; () -> void
set a, [zpc]
set b, [zpc+1]
jsr print_la

; zstr_ptr is now aimed at the last word, the one with the top bit set.
set a, [zstr_ptr]
set b, [zstr_ptr+1]
add b, 2
add a, ex
set [zpc], a
set [zpc+1], b
set pc, pop

:print_ba ; (ba) -> void
; Convert the byte address in A to a long address in A:B; high portion is 0
set b, a
set a, 0
set pc, print_la


; Prints the string from
:print_la ; (hi, lo) -> void
set [zstr_ptr], a
set [zstr_ptr+1], b
set [zstr_index], 0 ; This will cause zstr_next to read the string properly.
set [zstr_word], 0  ; Gotta make sure the top bit is clear.
set [shift], 0
set pc, zstr_main

:print_pc

