; IM 1 interrupts on the R800 core: INT every 3001 clocks (tbi.cpp) until OUT (3);
; the main loop sums with all the registers; prints the count and the sums
        org 100h
        di
        ld sp,0E000h
        ld hl,isr
        ld de,38h
        ld bc,isrend-isr
        ldir
        im 1
        ei
        ld ix,0
        ld iy,0
        ld hl,0
        ld b,0
loop1:  ld c,0
loop2:  ld a,b
        xor c
        ld e,a
        ld d,0
        add hl,de
        add ix,de
        inc iy
        ld a,(work)
        add a,e
        ld (work),a
        push hl
        pop hl
        ld a,c
        and 3Fh
        jr nz,nohalt
        halt
        ld a,(hcnt)
        inc a
        ld (hcnt),a
nohalt: dec c
        jr nz,loop2
        djnz loop1
        di
        ld (rhl),hl
        ld (rix),ix
        ld (riy),iy
        ld hl,(cnt)
        call phl
        ld hl,(rhl)
        call phl
        ld hl,(rix)
        call phl
        ld hl,(riy)
        call phl
        ld a,(work)
        ld h,a
        ld a,(hcnt)
        ld l,a
        call phl
        out (2),a
isr:    push af
        push hl
        ld hl,(cnt)
        inc hl
        ld (cnt),hl
        out (3),a
        pop hl
        pop af
        ei
        ret
isrend:
phl:    ld a,h
        call hex
        ld a,l
        call hex
        ld a,' '
        out (1),a
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
nib1:   out (1),a
        ret
cnt:    dw 0
rhl:    dw 0
rix:    dw 0
riy:    dw 0
work:   db 0
hcnt:   db 0
