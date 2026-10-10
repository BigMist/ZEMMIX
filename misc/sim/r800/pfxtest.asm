; DD / FD prefixes on the R800 core: prints "HL DE F" after each one
        org 100h
        ld sp,0E000h
        ; DD 04 (INC B): NOP on the R800 -> 0500
        ld b,5
        db 0DDh,04h
        ld h,b
        ld l,0
        call show
        ; DD DD 21 34 12: NOP pair, then LD HL,1234h -> 1234
        ld ix,0
        db 0DDh,0DDh,21h,34h,12h
        call show
        ; DD ED B0: NOP pair, then OR B -> F000
        ld b,0F0h
        xor a
        db 0DDh,0EDh,0B0h
        ld h,a
        ld l,0
        call show
        ; LD IX,5678h still works -> 5678
        ld ix,5678h
        push ix
        pop hl
        call show
        ; DD CB 00 36 with A = 80h, F = FFh: (IX+0) kept, F = 29h -> 1100 .... 29
        ld ix,mem
        ld a,11h
        ld (mem),a
        ld bc,80FFh
        push bc
        pop af
        db 0DDh,0CBh,00h,36h
        ld a,(mem)
        ld h,a
        ld l,0
        call show
        ; FD CB 00 30 with A = 01h, F = 00h: F = 00h -> 1100 .... 00
        ld iy,mem
        ld bc,0100h
        push bc
        pop af
        db 0FDh,0CBh,00h,30h
        ld a,(mem)
        ld h,a
        ld l,0
        call show
        jp 0
mem:    db 0
show:   push af
        push de
        push hl
        ld a,h
        call hex
        ld a,l
        call hex
        ld e,' '
        call pout
        pop hl
        pop de
        push de
        ld a,e
        ld (savee),a
        ld a,d
        call hex
        ld a,(savee)
        call hex
        ld e,' '
        call pout
        pop de
        pop af
        push af
        push af
        pop bc
        ld a,c
        call hex
        ld e,13
        call pout
        ld e,10
        call pout
        pop af
        ret
hex:    push af
        rrca
        rrca
        rrca
        rrca
        call nib
        pop af
nib:    and 0Fh
        add a,'0'
        cp '9'+1
        jr c,nib1
        add a,7
nib1:   ld e,a
pout:    push bc
        ld c,2
        call 5
        pop bc
        ret
savesp: dw 0
savee:  db 0
