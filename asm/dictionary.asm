; Dictionary and text-search support.

; Holds the raw Z-characters. Need extra space, in case of a long structure.
:encoding_zchars .reserve 16
:encoding_index dat 0
:encoded_words .reserve 3

:push_char ; (char) -> void
set b, [encoding_index]
set [b + encoding_zchars], a
set pc, pop

:encode_word ; (buffer, length, index)
; Initialize: set the whole buffer to 5s, and the index to 0.
set push, x
set push, y
set x, a
add x, c ; X is now the byte address for the next character.
set y, b ; Y is the length.

set [encoding_index], 0
set a, 9
:L5000
sub a, 1
set [a+encoding_zchars], 5
ife a, 0
  set pc, L5000

set a, pop
; Now there are 3 possibilities for each character.
; Lowercase letters
; A2 characters
; Raw encoding
:L5001
ife y, 0 ; When length is 0, we're done.
  set pc, L5002
set a, x
jsr rbba ; A is now the character.
ifg a, 96 ; 'a' = 97
  ifl a, 123 ; 'z' = 122
    set pc, L5003

; If we didn't jump, it wasn't a lowercase letter.
; Check it against A2.
set b, alphabet2
:L5004
ife [b], a
  set pc, L5005
add b, 1
ifl b, alphabets_top
  set pc, L5004

; If we're here, then we need to encode the multi-byte construction.
; 5, 6, hi_5, lo_5
set push, a ; Save the character.
set a, 5
jsr push_char
set a, 6
jsr push_char
set a, peek
shr a, 5
jsr push_char
set a, pop
and a, 0x1f
jsr push_char
set pc, L5006 ; Jump to the closer.

:L5005 ; B is the address of the character.
sub b, alphabet2
add b, 6
set push, b
set a, 5
jsr push_char ; Push a 5
set a, pop
jsr push_char ; Then the code.

set pc, L5006 ; Jump to the closing code.


:L5003 ; Lowercase character. 'a' = 97, should become 6. So subtract 91.
sub a, 91
jsr push_char
set pc, L5006 ; Jump to closing.


:L5006 ; Closing code, needs to check the end conditions.
; Advance the pointer in X, reduce the length in Y.
add x, 1
sub y, 1
ife y, 0
  set pc, L5002
ifg [encoding_index], 8 ; 9 or more Z-chars have been encoded.
  set pc, L5002

; Otherwise there's more encoding to do, so loop back to the top.
set pc, L5001


:L5002 ; We're done collecting characters, so encode them properly.
set a, encoding_zchars
set b, encoded_words
set c, 3

:L5007
set x, [a]
shl x, 5
bor x, [a+1]
shl x, 5
bor x, [a+2]
set [b], x
add b, 1
add a, 3
sub c, 1
ifg c, 0
  set pc, L5007

; Now we're all done and can return.
set y, pop
set x, pop
set pc, pop



; Compares the encoded dictionary word at the provided byte-address with the
; encoded_words. Returns -1 if the argument word comes before the global one,
; 0 if they match, and 1 if the argument word comes later.
:words_match ; (ba) -> ordering
set push, a
jsr rwba
set b, a ; Move the target word to B.
set a, 0
; First, most-significant word.
ifl b, [encoded_words]
  set a, -1
ifg b, [encoded_words]
  set a, 1

ifn a, 0
  set pc, L5010 ; Matched

; If it's still 0, check the next word.
set a, peek
add a, 2
jsr rwba
set b, a
set a, 0

; Second word
ifl b, [encoded_words+1]
  set a, -1
ifg b, [encoded_words+1]
  set a, 1

ifn a, 0
  set pc, L5010 ; Matched
ifl [version], 4
  set pc, L5010 ; In versions 1-3 it only uses 2 words.

; Third word
set a, peek
add a, 4
jsr rwba
set b, a
set a, 0

ifl b, [encoded_words+2]
  set a, -1
ifg b, [encoded_words+2]
  set a, 1

:L5010
set b, pop ; Drop the address. A is the result.
set pc, pop


; Expects the target word to be encoded into encoded_words.
; The dictionary is specified as an argument.
; TODO Currently this does a complete linear scan of the dictionary, nothing
; clever. It would be much faster to do a binary search. HOWEVER, the tokenise
; opcode can take a dictionary as a parameter - that dictionary need not be
; sorted, so that needs to be configured as an option, or split to a separate
; function.
; Returns 0 for words that are not found.
:search_dictionary ; (dictionary_table) -> address
set push, x
set push, y
set push, z
set x, a
jsr rbba ; Read the length of the separator table.
add x, a
add x, 1 ; X is now the address of the entry-length byte.
set a, x
jsr rbba ; Read the entry length.
set y, a

set a, x
add a, 1
jsr rwba
set z, a

; Now loop through all the entries in order.
add x, 3 ; X is now the address of the first entry.
:L5020
ife z, 0
  set pc, L5021 ; Not found
set a, x
jsr words_match ; A is now -1, 0 or 1.
; Since we're not doing a sorted search, we're just looking for 0.
ife a, 0
  set pc, L5022 ; Found
add x, y ; Bump to the next entry.
sub z, 1
set pc, L5020 ; And loop

:L5021 ; Failed to find the entry.
set a, 0
set pc, L5023 ; Closer

:L5022 ; Found the valid entry.
set a, x
; Fall through to the closer below.
:L5023
set z, pop
set y, pop
set x, pop
set pc, pop


; Scans a text buffer and separates it into words.
; Populates a parse buffer with the results.
; The format differs slightly based on Z-machine version.
; In v1-4, text[0] is the maximum size minus 1, text[1+] is the text.
; A 0 byte indicates the end of the text.
; In v5, text[0] is the maximum size, text[1] the actual size, text[2+] the
; text. There is no terminator in v5.
; The text buffer should already be correctly configured at this point.

; The dictionary is used for its word-terminating characters, as well as for
; lookup.

; When the flag is true, words that are not found are not modified in the parse
; buffer. That enables the flag from tokenise to be handled.
:lexical_scan ; (text, parse, dictionary, flag) -> void
; Because of the substantial differences in flow between v5 and older, split
; into two parts.
; They share the parse format, dictionary and flag though; those go into globals.
; In fact, they share the whole parsing state machine. The only difference is
; the next-character flow.
set [lex_text], a
set [lex_text_0], a
set [lex_parse], b
add [lex_parse], 2 ; Actual first parse record starts at parse[2]
set [lex_parse_0], b
set [lex_dictionary], c
set [lex_parse_flag], x
set [lex_word_start], -1 ; Signal that no word is currently running.
set [lex_state], lex_actions_outside_word
set a, c
jsr load_terminators

ifg [version], 4
  set pc, lexical_scan_v5
set pc, lexical_scan_v4

:lex_text dat 0
:lex_text_0 dat 0
:lex_length dat 0
:lex_parse dat 0
:lex_parse_0 dat 0
:lex_dictionary dat 0
:lex_parse_flag dat 0
:lex_word_start dat 0
:lex_state dat 0
:lex_next_char dat 0

:lexical_scan_v4 ; Expects text at text[1], with a 0 terminator.
add [lex_text], 1
add [lex_text_0], 1
set [lex_next_char], lex_next_v4
set pc, lex_next_v4

:lexical_scan_v5 ; Expects a length in text[1], text at 2+, no terminator.
set a, [lex_text]
add a, 1
jsr rbba
set [lex_length], a
add [lex_text], 2
add [lex_text_0], 2
set [lex_next_char], lex_next_v5
set pc, lex_next_v5



:lex_next_v4
set a, [lex_text]
set push, a
add [lex_text], 1
jsr rbba
set b, pop
ife a, 0
  set pc, [lex_state + lex_action_eof]
set pc, lex_process_char ; This part is common to both styles.

:lex_next_v5
ife [lex_length], 0
  set pc, L640
set a, [lex_text]
set push, a
add [lex_text], 1
sub [lex_length], 1
jsr rbba
set b, pop
set pc, lex_process_char

:L640 ; EOF found
set a, 0
set b, [lex_text]
set pc, [lex_state + lex_action_eof]

:lex_process_char ; (char, ba)
ife a, 32
  set pc, [lex_state + lex_action_space]

; Check each of the dictionary terminators.
set c, 0
:L630
ife c, [terminator_count]
  set pc, [lex_state + lex_action_letter] ; It's a letter.
ife [c + terminators], a
  set pc, [lex_state + lex_action_terminator] ; It's a terminator.
add c, 1
set pc, L630


; There are two different sets of actions when processing input,
; one for if we're in the middle of a word, and one for if we're outside a word.
; These are the offsets into a table.
; The character read is in A, the address it was read from in B (except for EOF)
.def lex_action_space, 0
.def lex_action_terminator, 1
.def lex_action_eof, 2
.def lex_action_letter, 3
.def lex_action_post_terminator, 4

; The three states, with four actions each.
:lex_actions_inside_word
dat lex_action_word_space, lex_action_word_terminator
dat lex_action_word_eof, lex_action_word_letter
:lex_actions_outside_word
dat lex_action_outside_space, lex_action_outside_terminator
dat lex_action_outside_eof, lex_action_outside_letter
:lex_actions_post_terminator
dat lex_action_postterm_space, lex_action_postterm_terminator
dat lex_action_postterm_eof, lex_action_postterm_letter



:lex_action_word_space ; Inside a word, found a space. Push and move to nonterm.
jsr push_word
set [lex_state], lex_actions_outside_word
set pc, [lex_next_char]

:lex_action_word_terminator ; Inside a word, found a terminator.
; Push and move to post-terminator.
set push, b
jsr push_word
set [lex_word_start], pop
set [lex_state], lex_action_post_terminator
set pc, [lex_next_char]

:lex_action_word_letter ; Inside a word, found a letter. Just keep moving.
set pc, [lex_next_char]

:lex_action_word_eof ; Inside a word, found the end. A is meaningless, but B is
; the address after the end, exactly what we need for calling push_word.
jsr push_word
set pc, pop ; Final return from the whole machine.


:lex_action_outside_space ; Outside a word, found a space. Just keep moving.
set pc, [lex_next_char]

:lex_action_outside_terminator ; Outside a word, found a terminator.
set [lex_word_start], b
set [lex_state], lex_actions_post_terminator
set pc, [lex_next_char]

:lex_action_outside_letter ; Outside a word, found a letter. Start a word.
set [lex_word_start], b
set [lex_state], lex_actions_inside_word
set pc, [lex_next_char]

:lex_action_outside_eof ; Outside a word, found EOF. Return.
set pc, pop


:lex_action_postterm_space ; After a terminator, found a space. Record
; terminator, move along.
jsr push_word
set [lex_state], lex_actions_outside_word
set pc, [lex_next_char]

:lex_action_postterm_terminator ; After a terminator, found another.
; Record the first, and set up for the second.
set push, b
jsr push_word
set [lex_word_start], pop
; Stay in postterm state.
set pc, [lex_next_char]

:lex_action_postterm_letter ; Record terminator, start word.
set push, b
jsr push_word
set [lex_word_start], pop
set [lex_state], lex_actions_inside_word
set pc, [lex_next_char]

:lex_action_postterm_eof ; Record word, return.
jsr push_word
set pc, pop



; Records a word that runs over the interval [lex_word_start, B).
; We try to find our word in the dictionary first. If it cannot be found and the
; flag is true, we simply advance the lex_parse pointer past its entry without
; changing it. (That supports the tokenise opcode.)
:push_word ; (current_letter, ba) -> void
; We need (buffer, length, index) to call encode_word.
; buffer is [lex_word_start], index is 0, length is B-A
set a, [lex_word_start]
sub b, a
set push, a
set push, b ; Save those two values for later.
set c, 0
jsr encode_word ; Returns nothing, but our word is now loaded in the globals.
set a, [lex_dictionary]
jsr search_dictionary ; A is now the pointer, or 0.
ife a, 0   ; If we didn't find the word,
  ifn [lex_parse_flag], 0 ; And the parse flag is true.
    set pc, L650 ; Then skip over the processing below.

; Check the maximum words to parse and the total so far.
; Only proceed if there's still space.
set a, [lex_parse_0]
jsr rbba
set push, a

set a, [lex_parse_0]
add a, 1
jsr rbba
set b, pop ; A is the (old) current and B the maximum.

add a, 1
ifg a, b ; If adding one more would exceed the maximum
  set pc, L651 ; Then skip writing anything.


; Record these pieces into the parse area.
; A is the word's address, and the stack holds ( ... start length )
set b, a
set a, [lex_parse]
jsr wwba ; Write the address at parse_record[0].

set a, [lex_parse]
add a, 2
set b, pop
jsr wbba ; Write the length at parse_record[2].

set a, [lex_parse]
add a, 3
set b, pop
jsr wbba ; And the index at parse_record[3].
; Now the stack is clean and the record written.
set pc, L651

; Now we're done, so jump to the finisher.

:L650 ; Clean up the stack since we're not writing the parse data.
set a, pop
set a, pop
; Fall through to L651 below.

:L651 ; Advance the parse buffer and count, whether we populated it or not.
set a, [lex_parse_0]
add a, 1
set push, a
jsr rbba ; A is now the number of words so far.

add a, 1 ; Increment it.
set b, a
set a, pop
jsr wbba ; And write it back.

; Also advance the running pointer to the parse buffer.
add [lex_parse], 4

set pc, pop ; All done!


:terminators .reserve 8
:terminator_count dat 0

:load_terminators ; (dictionary) -> void
set push, x
set push, y
set x, a
jsr rbba ; Number of terminators.
set [terminator_count], a
add x, 1
set y, 0
:L600
ife y, [terminator_count]
  set pc, L601
set a, x
add a, y
jsr rbba
set [y+terminators], a
add y, 1
set pc, L600

:L601
set y, pop
set x, pop
set pc, pop

