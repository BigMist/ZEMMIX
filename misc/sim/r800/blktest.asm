; block instruction test for the R800 core: prints results as hex
        org 100h
        ld sp,0E000h
        ; fill 4000h..412Bh with i*7
        ld hl,4000h
        ld bc,300
        xor a
fill:   ld (hl),a
        add a,7
        inc hl
        dec bc
        ld e,a
        ld a,b
        or c
        ld a,e
        jr nz,fill
        ; LDIR 4000h -> 5000h, 300 bytes
        ld hl,4000h
        ld de,5000h
        ld bc,300
        ldir
        push hl
        push de
        push bc
        call cmp1          ; A = mismatches (0)
        call hex
        pop bc
        pop de
        pop hl
        ld a,h
        call hex           ; 41
        ld a,l
        call hex           ; 2C
        ld a,d
        call hex           ; 51
        ld a,e
        call hex           ; 2C
        ld a,b
        call hex
        ld a,c
        call hex           ; 0000
        call crlf
        ; LDDR 412Bh -> 612Bh
        ld hl,412Bh
        ld de,612Bh
        ld bc,300
        lddr
        ld hl,6000h
        ld a,(hl)
        call hex           ; 00
        ld a,(612Bh)
        call hex           ; 299*7 & FF = 2Dh... (299*7=2093 -> 2D)
        call crlf
        ; CPIR: find 0x31 (i=7: 49=0x31) in 4000h
        ld hl,4000h
        ld bc,300
        ld a,31h
        cpir
        push af
        ld a,h
        call hex
        ld a,l
        call hex           ; 4008
        ld a,b
        call hex
        ld a,c
        call hex           ; 0124 (300-8)
        pop bc             ; flags in C
        ld a,c
        call hex
        call crlf
        ; CPIR not found: A=0xFF? (0..255 step 7 never 0xFF? i*7 mod 256: 0xFF reached at i=219 since 7*219=1533=0x5FD -> FD... ) search 1, never multiple
        ld hl,4000h
        ld bc,20
        ld a,1
        cpir
        push af
        ld a,b
        call hex
        ld a,c
        call hex           ; 0000
        pop bc
        ld a,c
        call hex
        call crlf
        jp 0
cmp1:   ld hl,4000h
        ld de,5000h
        ld bc,300
        ld ixl,0
cmpl:   ld a,(de)
        cp (hl)
        jr z,cmpok
        inc ixl
cmpok:  inc hl
        inc de
        dec bc
        ld a,b
        or c
        jr nz,cmpl
        ld a,ixl
        ret
crlf:   ld e,13
        call pout
        ld e,10
        jr pout
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
pout:   push bc
        push hl
        push de
        ld c,2
        call 5
        pop de
        pop hl
        pop bc
        ret
