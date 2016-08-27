.include asm/core.asm
.include asm/memory.asm
.include asm/random.asm
.include asm/cpu.asm
.include asm/0op.asm
.include asm/1op.asm
.include asm/2op.asm
.include asm/var.asm
.include asm/ext.asm
.include asm/strings.asm
.include asm/dictionary.asm
.include asm/objects.asm
.include asm/screen.asm
.include asm/debug.asm

:hw_display dat 0
:hw_disk dat 0
:hw_keyboard dat 0

:main
jsr detect_hardware
jsr setup_interrupts
jsr init_screen
jsr await_disk_inserted
set pc, zrestart


:str_insert_disk .asciiz "Insert a story disk"

.def disk_state_no_media, 0
.def disk_state_ready, 1
.def disk_state_ready_wp, 2
.def disk_state_busy, 3

:await_disk_inserted
set a, 0 ; Polls the device.
hwi [hw_disk]
ifn b, disk_state_no_media
  set pc, pop

set a, str_insert_disk
jsr emit_native_string
:L100
set a, 0
hwi [hw_disk]
ife b, disk_state_no_media
  set pc, L100
jsr clear_screen
set pc, pop


; Scans the attached hardware and connects the LEM1802 display, M35d disk, and
; generic keyboard when detected.
:detect_hardware ; ()
set push, x
set push, y
set push, z
set push, I
hwn i  ; Number of devices in I
:_detect_loop
ife i, 0
  set pc, _detect_done

sub i, 1
hwq i  ; B:A is the device ID, C the version, Y:X the manufacturer
set z, device_table

:_detect_check_device
; If the manufacturer is 0, we'll accept any compatible device.
ife [z], 0
  ife [z+1], 0
    set pc, _detect_check_id

; Check the manufacturer
ife [z], y
  ife [z+1], x
    set pc, _detect_check_id

; If we get here, the manufacturer doesn't match.
set pc, _detect_next_entry

:_detect_check_id
ife [z+2], b
  ife [z+3], a
    set pc, _detect_device_found

; If we get here, the ID doesn't match.
:_detect_next_entry
add z, device_size
ifl z, device_table_end
  set pc, _detect_check_device

set pc, _detect_next_device

; If we jumped to here, then store the device number (I) in the target location.
:_detect_device_found
set z, [z+4] ; Z is now the target address.
set [z], i   ; Which now holds the device number.
; Fall through the next_device

; Subtract 1 from I and check the next device.
:_detect_next_device
set pc, _detect_loop

; Called when we've exhausted all devices returned by the hardware.
:_detect_done
set i, pop
set z, pop
set y, pop
set x, pop
set pc, pop


; Device table
; Each device has a manufacturer (hi, lo), ID (hi, lo), and destination address.
.def device_size, 5
:device_table
; Generic keyboard
dat 0,      0,      0x30cf, 0x7406, hw_keyboard
; LEM1802 display - "new" ID
dat 0x1c6c, 0x8b36, 0x734d, 0xf615, hw_display
; LEM1802 display - "old" ID -- TODO What's the difference between them?
dat 0x1c6c, 0x8b36, 0x7349, 0xf615, hw_display
; M35fd floppy drive
dat 0x1eb3, 0x7e91, 0x4fd5, 0x24c5, hw_disk
:device_table_end


; Sets up interrupt handler and enables interrupts for all devices we care to
; watch for interrupts.
; For now, that just means the disk, since it's always async.
:setup_interrupts ; () -> void
set push, x
iaq 1 ; Force interrupt queueing on, to allow setup to finish.
ias int_handler

; Set the disk interrupt message.
set x, irq_disk
set a, 1 ; M35fd disk message for setting the interrupt to X.
hwi [hw_disk]

:int_handler ; Interrupt handlers are magic!
ifg a, irq_count
  rfi 0

sub a, 1
add a, interrupt_vector
set pc, [a]


:interrupt_disk_flag dat 0 ; 1 when there's been an interrupt.

; Check if the interrupt_await_disk value is nonzero.
; If it is, set interrupt_spinner to that value and set the await back to 0.
; Then the next time we're spinning waiting for an interrupt, it'll go to the
; spinner target.
; That avoids a race condition where the interrupt arrives before we're really
; spinning.
:int_handler_disk
set [interrupt_disk_flag], 1
rfi 0


.def irq_disk, 1
.def irq_count, 1 ; The number of IRQs

:interrupt_vector
dat int_handler_disk
:interrupt_vector_top

; Beware of race conditions!
; Start the disk activity first, then call this function.
; Returns when the disk is READY or READY_WP. Otherwise, spins waiting for
; interrupts.
:await_disk_ready ; () -> viud
; Clear the interrupt flag first thing, in case it fires while we're screwing
; around here.
set [interrupt_disk_flag], 0
; First, check the current state - it might already be ready!
set a, 0
hwi [hw_disk] ; B is now the state and C the error message.
ife b, disk_state_ready
  set pc, L200
ife b, disk_state_ready_wp
  set pc, L200

:L201
ife [interrupt_disk_flag], 0
  set pc, L201

; At this point, the disk is ready.
:L200
set pc, pop



; TESTING
; Dumps all strings in the system, one at a time.
; Waits for any keystroke, then clears the screen and prints the next one.
:dump_all_strings ; () -> void
set push, x
set x, zm_string_table
:L204
ife x, zm_string_table_top
  set pc, L205

; Step 1: Print-paddr the string.
set a, [x]
jsr print_paddr
; Step 2: Await a keystroke.
jsr await_any_key
jsr clear_screen
add x, 1
set pc, L204

:L205
set x, pop
set pc, pop



:await_any_key ; () -> key
set a, 1 ; GET_NEXT
hwi [hw_keyboard]
ife c, 0
  set pc, await_any_key
set a, c
set pc, pop


; String table. These are v5 packed addresses, so I they're the Z-machine
; address over four.
:zm_string_table
dat 0x4b26 ; S001 "An old leather bag, bulging with coins, is here."
dat 0x4b2e ; S002 "
;(Close cover before striking)
;
;YOU too can make BIG MONEY in the exciting field of PAPER SHUFFLING!
;
;Mr. Anderson of Muddle, Mass. says: "Before I took this course I was a lowly
;bit twiddler. Now with what I learned at GUE Tech I feel really important and
;can obfuscate and confuse with the best."
;
;Dr. Blank had this to say: "Ten short days ago all I could look forward to was
;a dead-end job as a doctor. Now I have a promising future and make really big
;Zorkmids."
;
;GUE Tech can't promise these fantastic results to everyone. But when you earn
;your degree from GUE Tech, your future will be brighter."
dat 0x4b94 ; S003 "You have come to a dead end in the maze."
dat 0x4b9a ; S004 "You have entered the Land of the Living Dead. Thousands of lost
;souls can be heard weeping and moaning. In the corner are stacked the remains
;of dozens of previous adventurers less fortunate than yourself. A passage exits
;to the north."
dat 0x4bbd ; S005 "You have entered a low cave with passages leading northwest and
;east."
dat 0x4bc5 ; S006 "You haven't a prayer of getting the coffin down there."
dat 0x4bcd ; S007 "You have come to a dead end in the mine."
dat 0x4bd3 ; S008 " has no effect."
dat 0x4bd6 ; S009 "You have two choices: 1. Leave  2. Become dinner."
dat 0x4bdf ; S010 "Try the water, too."
dat 0x4be3 ; S011 "Try throwing the knife or attacking someone with it."
dat 0x4bec ; S012 "It requires the bell, book, and candles."
dat 0x4bf2 ; S013 "Try them all. You should be able to find out."
dat 0x4bfa ; S014 "clockwork canary - 6 - 4 - in the egg"
dat 0x4c01 ; S015 "... poured water on something burning?"
dat 0x4c07 ; S016 "over your head."
dat 0x4c09 ; S017 "Kill him with the sword."
dat 0x4c0d ; S018 "Use the buttons in the Maintenance Room."
dat 0x4c13 ; S019 "Use the gunk in the tube."
dat 0x4c17 ; S020 "By the way, have you ever taken a close look at the word ARAGAIN?"
dat 0x4c22 ; S021 "Use the garlic."
dat 0x4c25 ; S022 "sapphire bracelet - 5 - 5 - Gas Room"
dat 0x4c2c ; S023 "Storm-tossed trees block your way."
dat 0x4c32 ; S024 "Oh, no! You have walked into the slavering fangs of a lurking
;grue!"
dat 0x4c3c ; S025 " knocks out the "
dat 0x4c3e ; S026 "Play ZORK II."
dat 0x4c42 ; S027 "I'm lost in the Forest."
dat 0x4c46 ; S028 "First, the first solution:"
dat 0x4c4b ; S029 "(Well, no one said they would work in a draft.) You can't carry a
;light source in. There is another way."
dat 0x4c5a ; S030 "... read the matchbook?"
dat 0x4c5e ; S031 "At the end of the chain is a basket."
dat 0x4c64 ; S032 "On the ground is a red hot bell."
dat 0x4c69 ; S033 "On the altar is a large black book, open to page 569."
dat 0x4c72 ; S034 "On the table is an elongated brown sack, smelling of hot peppers."
dat 0x4c7d ; S035 "On the shore lies Poseidon's own crystal trident."
dat 0x4c86 ; S036 "On the two ends of the altar are burning candles."
dat 0x4c8e ; S037 "On the ground is a pile of leaves."
dat 0x4c93 ; S038 "On the ground is a large platinum bar."
dat 0x4c98 ; S039 "At the end of the rainbow is a pot of gold."
dat 0x4c9f ; S040 "    "
dat 0x4ca0 ; S041 "With great effort, you open the window far enough to allow entry."
dat 0x4cab ; S042 " parries."
dat 0x4cad ; S043 "It can be unlocked only from below."
dat 0x4cb2 ; S044 "Try winding it in the forest."
dat 0x4cb7 ; S045 "It cannot be knocked down."
dat 0x4cbb ; S046 "It cannot be destroyed."
dat 0x4cbe ; S047 "It cannot be opened."
dat 0x4cc1 ; S048 "It can be used as a weapon, but isn't really necessary for
;anything."
dat 0x4ccc ; S049 "Touching the mirror in one transports you to the other."
dat 0x4cd5 ; S050 "Yes."
dat 0x4cd6 ; S051 ""It's too narrow for most insects.""
dat 0x4cdb ; S052 "... said WAIT or SCORE while dead (as a spirit)?"
dat 0x4ce6 ; S053 "See the previous question."
dat 0x4ceb ; S054 "It doesn't oil the bolt well."
dat 0x4cef ; S055 "U. N. E. S. N."
dat 0x4cf3 ; S056 "Need a Drafty Room light source?"
dat 0x4cf9 ; S057 "See the alternative Cyclops answer."
dat 0x4cfe ; S058 "Treasures: Their Values, Locations."
dat 0x4d05 ; S059 "... tried swearing at ZORK I?"
dat 0x4d0c ; S060 "... tried anything nasty with the bodies in Hades?"
dat 0x4d14 ; S061 "... tried to take yourself (or the Thief, Troll or Cyclops)?"
dat 0x4d1f ; S062 "... tried cutting things with the knife or sword?"
dat 0x4d27 ; S063 " and devoured you!"
dat 0x4d2a ; S064 "Too late for that."
dat 0x4d2d ; S065 " by an inch."
dat 0x4d2f ; S066 " by a mile."
dat 0x4d31 ; S067 " and knocks it spinning."
dat 0x4d34 ; S068 "You must unlock it."
dat 0x4d37 ; S069 "You must open the egg first."
dat 0x4d3c ; S070 "Still, how do I get through the Maze?"
dat 0x4d42 ; S071 "You must exorcise the evil spirits."
dat 0x4d48 ; S072 "You must activate the panel. (Green bubble lights up)."
dat 0x4d51 ; S073 "Diamonds are pure carbon in a crystalline form. They are created
;under tremendous heat and pressure."
dat 0x4d61 ; S074 "You may appear in the forest with your belongings scattered
;(valuables below ground, nonvaluables above)."
dat 0x4d72 ; S075 "You may wander as a spirit until you find a way to resurrect
;yourself."
dat 0x4d7d ; S076 "How Points are Scored."
dat 0x4d81 ; S077 "An ornamented sceptre, tapering to a sharp point, is here."
dat 0x4d8b ; S078 "" Flood Control Dam #3
;
;FCD#3 was constructed in year 783 of the Great Underground Empire to harness
;the mighty Frigid River. This work was supported by a grant of 37 million
;zorkmids from your omnipotent local tyrant Lord Dimwit Flathead the Excessive.
;This impressive structure is composed of 370,000 cubic feet of concrete, is 256
;feet tall at the center, and 193 feet wide at the top. The lake created behind
;the dam has a volume of 1.7 billion cubic feet, an area of 12 million square
;feet, and a shore line of 36 thousand feet.
;
;The construction of FCD#3 took 112 days from ground breaking to the dedication.
;It required a work force of 384 slaves, 34 slave drivers, 12 engineers, 2
;turtle doves, and a partridge in a pear tree. The work was managed by a command
;team composed of 2345 bureaucrats, 2347 secretaries (at least two of whom could
;type), 12,256 paper shufflers, 52,469 rubber stampers, 245,193 red tape
;processors, and nearly one million dead trees.
;
;We will now point out some of the more interesting features of FCD#3 as we
;conduct you on a guided tour of the facilities:
;
        ;1) You start your tour here in the Dam Lobby. You will notice on your
;right that...."
dat 0x4e50 ; S079 "That was just a bit too far down."
dat 0x4e56 ; S080 "The axe sweeps past as you jump aside."
dat 0x4e5c ; S081 "The axe crashes against the rock, throwing sparks!"
dat 0x4e64 ; S082 "The axe gets you right in the side. Ouch!"
dat 0x4e6a ; S083 "An axe stroke makes a deep wound in your leg."
dat 0x4e72 ; S084 "The axe hits your "
dat 0x4e75 ; S085 "The axe knocks your "
dat 0x4e77 ; S086 "Q = main menu"
dat 0x4e7a ; S087 "They can be taken, counted, or burned."
dat 0x4e81 ; S088 "You need the skeleton key."
dat 0x4e85 ; S089 "The artist was sloppy."
dat 0x4e89 ; S090 "For a hint, turn the page in the black book."
dat 0x4e90 ; S091 "The altar has magical powers."
dat 0x4e95 ; S092 "You need the wrench."
dat 0x4e98 ; S093 "You need the air pump, which is north of the Reservoir."
dat 0x4e9f ; S094 "Matches."
dat 0x4ea1 ; S095 "Objects, including light sources, can be placed in the basket. The
;basket can be lowered and raised."
dat 0x4eb0 ; S096 "Objects seem to move or disappear."
dat 0x4eb6 ; S097 "A hot pepper sandwich is here."
dat 0x4ebb ; S098 "The "
dat 0x4ebc ; S099 "The blow lands, making a shallow gash in the "
dat 0x4ec3 ; S100 "The butt of his stiletto cracks you on the skull, and you stagger
;back."
dat 0x4ecd ; S101 "No one can fix it. Really!"
dat 0x4ed2 ; S102 "Are the leaves useful for anything?"
dat 0x4ed8 ; S103 "Wait until the reservoir is empty, then close the gates."
dat 0x4ee1 ; S104 "You'll never reach the rope."
dat 0x4ee6 ; S105 "Brushing your teeth with it is not sensible."
dat 0x4eec ; S106 "You'll know when the time comes."
dat 0x4ef2 ; S107 "The blue button causes a water pipe to burst."
dat 0x4ef9 ; S108 "The brown bubble deactivates the control panel."
dat 0x4f01 ; S109 "Evidently the ancient Zorkers did not have strong
;truth-in-advertising laws. Take nothing for granite."
dat 0x4f11 ; S110 "Why does the sword glow?"
dat 0x4f15 ; S111 "General Questions"
dat 0x4f19 ; S112 "... waved the sceptre while standing on the rainbow?"
dat 0x4f22 ; S113 "This is a forest, with trees in all directions. To the east, there
;appears to be sunlight."
dat 0x4f2e ; S114 "This is a dimly lit forest, with large trees all around."
dat 0x4f36 ; S115 "This is a path winding through a dimly lit forest. The path heads
;north-south here. One particularly large tree with some low branches stands at
;the edge of the path."
dat 0x4f4c ; S116 "This is the attic. The only exit is a stairway leading down."
dat 0x4f54 ; S117 "This is a small room with passages to the east and south and a
;forbidding hole leading west. Bloodstains and deep scratches (perhaps made by
;an axe) mar the walls."
dat 0x4f69 ; S118 "The chasm probably leads straight to the infernal regions."
dat 0x4f71 ; S119 "This is an art gallery. Most of the paintings have been stolen by
;vandals with exceptional taste. The vandals left through either the north or
;west exits."
dat 0x4f86 ; S120 "This appears to have been an artist's studio. The walls and floors
;are splattered with paints of 69 different colors. Strangely enough, nothing of
;value is hanging here. At the south end of the room is an open door (also
;covered with paint). A dark and narrow chimney leads up from a fireplace;
;although you might be able to get up it, it seems unlikely you could get back
;down."
dat 0x4fbb ; S121 "This is part of a maze of twisty little passages, all alike."
dat 0x4fc5 ; S122 "This is part of a maze of twisty little passages, all alike. A
;skeleton, probably the remains of a luckless adventurer, lies here."
dat 0x4fd8 ; S123 "The cyclops doesn't look like he'll let you past."
dat 0x4fde ; S124 "This is a long passage. To the west is one entrance. On the east
;there is an old wooden door, with a large opening in it (about cyclops sized)."
dat 0x4ff0 ; S125 "This is a large room, whose east wall is solid granite. A number
;of discarded bags, which crumble at your touch, are scattered about on the
;floor. There is an exit down a staircase."
dat 0x5008 ; S126 "The channel is too narrow."
dat 0x500c ; S127 "This is a tiny cave with entrances west and north, and a staircase
;leading down."
dat 0x5015 ; S128 "This is a tiny cave with entrances west and north, and a dark,
;forbidding staircase leading down."
dat 0x5021 ; S129 "This is a cold and damp corridor where a long east-west passageway
;turns into a southward path."
dat 0x502f ; S130 "This is a long and narrow corridor where a long north-south
;passageway briefly narrows even further."
dat 0x503d ; S131 "This is a winding passage. It seems that there are only exits on
;the east and north."
dat 0x5047 ; S132 "This is an ancient room, long under water. There is an exit to the
;south and a staircase leading up."
dat 0x5052 ; S133 "This is a narrow east-west passageway. There is a narrow stairway
;leading down at the north end of the room."
dat 0x505e ; S134 "This is a circular stone room with passages in all directions.
;Several of them have unfortunately been blocked by cave-ins."
dat 0x5070 ; S135 "This cave has exits to the west and east, and narrows to a crack
;toward the south. The earth is particularly damp here."
dat 0x5081 ; S136 "This is a high north-south passage, which forks to the northeast."
dat 0x508a ; S137 "This is a room which looks like an Egyptian tomb. There is an
;ascending staircase to the west."
dat 0x5095 ; S138 "This is the north end of a large temple. On the east wall is an
;ancient inscription, probably a prayer in a long-forgotten language. Below the
;prayer is a staircase leading down. The west wall is solid granite. The exit to
;the north end of the room is through huge marble pillars."
dat 0x50b7 ; S139 "This is the south end of a large temple. In front of you is what
;appears to be an altar. In one corner is a small hole in the floor which leads
;into darkness. You probably could not get back up it."
dat 0x50d0 ; S140 "This room appears to have been the waiting room for groups touring
;the dam. There are open doorways here to the north and east marked "Private",
;and there is a path leading south over the top of the dam."
:zm_string_table_top

