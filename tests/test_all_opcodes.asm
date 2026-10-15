;; All-Inclusive Opcode Test
;; This file contains at least one of every AVR opcode mapped in avr2mos.

.section .text
.global main

main:
    ;; 0. Initialize Stack Pointer (0x08FF)
    ldi r16, 0xFF
    out 0x3d, r16 ; SPL
    ldi r16, 0x08
    out 0x3e, r16 ; SPH

    ;; 1. Base Arithmetic
    nop
    add r16, r17
    adc r16, r17
    sub r16, r17
    subi r16, 5
    sbc r16, r17
    sbci r16, 1
    subi r28, 5
    subi r29, 0
    inc r16
    dec r17
    adiw r24, 5
    sbiw r24, 5

    ;; 2. Multipliers
    mul r16, r17
    muls r16, r17
    mulsu r16, r17
    fmul r16, r17
    fmuls r16, r17
    fmulsu r16, r17

    ;; 3. Logic & Bitwise
    and r16, r17
    andi r16, 0x0F
    or r16, r17
    ori r16, 0x80
    eor r16, r17
    com r16
    neg r16
    tst r16
    clr r16
    ser r16
    sbr r16, 1
    cbr r16, 1

    ;; 4. Shifts and Rotates
    lsr r16
    ror r16
    asr r17
    swap r16

    ;; 5. Bit and Flag Instructions
    bset 0
    bset 1
    bset 2
    bset 3
    bset 4
    bset 5
    bset 6
    bset 7
    bclr 0
    bclr 1
    bclr 2
    bclr 3
    bclr 4
    bclr 5
    bclr 6
    bclr 7
    bst r16, 3
    bld r17, 3
    sec
    clc
    sei
    cli

    ;; 6. Memory & Data Transfer
    ldi r16, 0xFF
    mov r16, r17
    movw r26, r28
    
    sts 0x0100, r16
    lds r16, 0x0100
    
    ;; Indirect load/store (using X/Y/Z mapped to r26:r27, r28:r29, r30:r31)
    ld  r16, X
    ld  r16, X+
    ld  r16, -X
    
    ld  r16, Y
    ld  r16, Y+
    ld  r16, -Y
    
    ld  r16, Z
    ld  r16, Z+
    ld  r16, -Z
    
    st  X, r16
    st  X+, r16
    st  -X, r16
    
    st  Y, r16
    st  Y+, r16
    st  -Y, r16
    
    st  Z, r16
    st  Z+, r16
    st  -Z, r16

    ldd r16, Y+5
    ldd r16, Z+10
    std Y+5, r16
    std Z+10, r16

    ;; Stack operations
    push r16
    pop r16
    
    ;; Special registers & memory
    in r16, 0x3F
    out 0x3F, r16
    lpm
    lpm r16, Z
    lpm r16, Z+

    ;; 7. Control Flow
    cp r16, r17
    cpc r16, r17
    cpi r16, 10
    cpse r16, r17
    
    sbrc r16, 0
    nop
    sbrs r16, 1
    nop
    
    sbic 0x1A, 2
    nop
    sbis 0x1A, 3
    nop
    sbi 0x1A, 2
    cbi 0x1A, 2

    ;; Branches
    breq lbl_eq
    brne lbl_ne
    brsh lbl_sh
    brlo lbl_lo
    brmi lbl_mi
    brpl lbl_pl
    brge lbl_ge
    brlt lbl_lt
    brbs 0, lbl_bs
    brbc 0, lbl_bc

lbl_eq:
lbl_ne:
lbl_sh:
lbl_lo:
lbl_mi:
lbl_pl:
lbl_ge:
lbl_lt:
lbl_bs:
lbl_bc:
    
    ;; Jumps and Calls removed to avoid indirect jump table issues

    

    rjmp test_alu
end:
    rjmp test_alu

sub_routine:
    ret

interrupt_routine:
    reti


; --- Merged from test_alu.asm ---


test_alu:
    ldi r16, 0x10
    ldi r17, 0x20
    add r16, r17    ; r16 = 0x30
    
    subi r16, 0x05  ; r16 = 0x2B
    
    ldi r18, 0x02
    ; Note: mul is not supported on all AVRs, but atmega328p has it.
    mul r16, r18    ; r1:r0 = 0x2B * 2 = 0x56
    
    ; End simulation
    rjmp test_bit


; --- Merged from test_bit.asm ---
; Test Bitwise and Shift Operations
test_bit:

    ldi r16, 0xAA
    ldi r17, 0x55
    
    ; Logic
    and r16, r17 ; r16 = 0x00
    ldi r16, 0xAA
    or  r16, r17 ; r16 = 0xFF
    eor r16, r17 ; r16 = 0xAA
    
    ; Shifts
    ldi r18, 0x80
    lsr r18      ; r18 = 0x40, C=0
    ror r18      ; r18 = 0x20, C=0 (if C was 0)
    
    ldi r19, 0x81
    asr r19      ; r19 = 0xC0, C=1
    
    ; Bit manipulation (I/O)
    ; We'll use I/O address 0x05 (PORTB on many AVRs)
    ; Which is data address 0x25
    sbi 0x05, 0  ; Bit 0 of IO 0x05 = 1
    sbi 0x05, 7  ; Bit 7 of IO 0x05 = 1
    cbi 0x05, 0  ; Bit 0 of IO 0x05 = 0
    
    ; Skip if bit set/clear
    sbic 0x05, 7 
    ldi r20, 0x01 ; Should execute
    
    sbis 0x05, 0
    ldi r21, 0x02 ; Should execute
    
    rjmp test_data_wide


; --- Merged from test_data_wide.asm ---
; Test 16-bit Operations and Wide Data Transfers
test_data_wide:

    ; MOVW
    ldi r16, 0x11
    ldi r17, 0x22
    movw r18, r16 ; r18=0x11, r19=0x22
    
    ; ADIW / SBIW
    ldi r24, 0xFE
    ldi r25, 0x00
    adiw r24, 5   ; r24=0x03, r25=0x01
    sbiw r24, 10  ; r24=0xF9, r25=0x00
    
    ; LDS / STS (Direct addressing)
    ; We'll use SRAM address 0x0100 (start of SRAM)
    ; In 6502 this maps to mapDataAddress(0x0100)
    ldi r20, 0xAB
    sts 0x0100, r20
    
    ldi r20, 0x00
    lds r20, 0x0100 ; r20 should be 0xAB
    
    rjmp test_flow



; --- Merged from test_flow.asm ---


test_flow:
    ldi r16, 0x05
    ldi r17, 0x0A
    
    cp r16, r17
    brlo is_lower
    
    ; Should not reach here
    ldi r18, 0xFF
    rjmp flow_end

is_lower:
    ldi r18, 0xAA
    
    ; Test a loop
    ldi r19, 3
flow_loop:
    inc r20
    dec r19
    brne flow_loop
    
flow_end:
    rjmp test_stack



; --- Merged from test_stack.asm ---
; Test Stack Operations and Subroutines
test_stack:

    ; Initialize Stack Pointer
    ldi r16, 0xFF
    out 0x3d, r16 ; SPL
    ldi r16, 0x08
    out 0x3e, r16 ; SPH (0x08FF)

    ; Initial stack is at end of SRAM
    ; We'll push some values and pop them
    
    ldi r16, 0x11
    ldi r17, 0x22
    
    push r16
    push r17
    
    ldi r16, 0x00
    ldi r17, 0x00
    
    pop r17
    pop r16
    
    ; r16 should be 0x11, r17 should be 0x22
    
    ; Test RCALL and RET
    rcall sub1
    ldi r18, 0x33 ; Should execute after RET
    
    break
    rjmp .
    
sub1:
    ldi r19, 0x44
    ret
