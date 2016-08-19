.include asm/core.asm
.include asm/memory.asm
.include asm/cpu.asm
.include asm/strings.asm
.include asm/screen.asm

:hw_display dat 0
:hw_disk dat 0
:hw_keyboard dat 0

:main
jsr detect_hardware
jsr setup_interrupts
jsr init_screen
jsr await_disk_inserted
; Load the dynamic and static memory regions at memory_base.
jsr load_low_mem
; Set the version
set a, header_version
jsr rbba
set [version], a

; Testing the string output.
; 0x1938c/4 = 0x64e3
set a, 0x64e3 ; "How silly!"
jsr print_paddr
sub pc, 1


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

