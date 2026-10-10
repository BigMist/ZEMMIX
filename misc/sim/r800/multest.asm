; MULUB / MULUW test for the R800 core: prints "HL DE F" after each one
        org 100h
        ld sp,0E000h
        ; MULUB A,B: 12h x 34h = 03A8h (C: high byte not zero)
        ld a,12h
        ld b,34h
        db 0EDh,0C1h
        call show
        ; MULUB A,C: 0 x 5 = 0 (Z)
        xor a
        ld c,5
        db 0EDh,0C9h
        call show
        ; MULUB A,E: 0Fh x 0Fh = 00E1h (no C)
        ld a,0Fh
        ld e,0Fh
        db 0EDh,0D9h
        call show
        ; MULUW HL,BC: 1234h x 5678h = 06260060h
        ld hl,1234h
        ld bc,5678h
        db 0EDh,0C3h
        call show
        ; MULUW HL,SP: 0100h x 0020h = 00002000h (no C)
        ld (savesp),sp
        ld sp,0020h
        ld hl,0100h
        db 0EDh,0F3h
        ld sp,(savesp)
        call show
        ; SLL B (CB 30): R800 = SLA: 81h -> 02h
        ld b,81h
        db 0CBh,30h
        ld h,b
        ld l,0
        call show
        jp 0
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
