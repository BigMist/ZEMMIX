; one instruction per test, separated by markers: OUT (0FEh),A before each
        org 0
        ld sp,0F000h
        ld hl,8000h
        ld ix,8100h
        ld iy,8200h
        ld bc,0010h
        ld de,9000h
t:      macro
        out (0FEh),a
        endm
        t
        t
        nop
        t
        ld b,c
        t
        ld b,5
        t
        ld a,(hl)
        t
        ld (hl),a
        t
        ld hl,8000h
        t
        ld a,(8000h)
        t
        ld (8000h),a
        t
        add a,b
        t
        inc b
        t
        inc (hl)
        t
        push bc
        t
        pop bc
        t
        jp j1
j1:     t
        jr j2
j2:     t
        call c1
        t
        jr c2
c1:     ret
c2:     t
        ex de,hl
        t
        ex de,hl
        t
        ldi
        t
        out (10h),a
        t
        in a,(10h)
        t
        bit 3,b
        t
        set 3,(hl)
        t
        ld a,(ix+5)
        t
        ld (ix+5),a
        t
        add ix,bc
        t
        djnz d1
d1:     t
        add hl,bc
        t
        adc hl,bc
        t
        ld bc,4
        t
        ldir
        t
        neg
        t
        halt
