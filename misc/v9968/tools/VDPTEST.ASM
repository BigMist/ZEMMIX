; VDPTEST.COM: MSX2 / MSX2+ VDP test for ZEMMIX (V9968), MSX-DOS.
; Build with pasmo --equ DISPON=1 (VDPTESTD.COM): the same with the display and the
; sprites on, as games draw; add --equ FASTHMMC=1 (VDPTESTF.COM): HMMC bytes
; through 9Bh back to back, no pause and no TR polling.
; Assemble: pasmo VDPTEST.ASM VDPTEST.COM
;
; Checks through the CPU ports what Zanac EX does, reading back with 98h:
;   1  VRAM 128 KB written and read with R#14 (8 blocks of 16 KB)
;   2  address set, then R#14 written, then data (the pointer must stay)
;   3  SCREEN 5 commands on page 1 / page 0: HMMV, HMMC through 9Bh with
;      R#17 = ACh, HMMM page 1 -> page 0, LMMM TIMP, PSET
; Interrupts are off during the tests; the text screen is set again with
; the BIOS INITXT at the end and the results are printed.

BDOS    equ 5
CALSLT  equ 001Ch
EXPTBL  equ 0FCC1h
INITXT  equ 006Ch
P_DATA  equ 98h
P_CTRL  equ 99h
P_IND   equ 9Bh

        org 100h

start:  di
        ld hl,rslt
        ld b,RSLTLEN
        xor a
clr:    ld (hl),a
        inc hl
        djnz clr

        ld hl,scr5              ; SCREEN 5 (linear VRAM), display off
        call wregs

        ; ---- 1: 128 KB write / read ------------------------------------
        xor a
        ld (pg),a
t1w:    call t1setw
        ld hl,0
t1wl:   call t1val
        out (P_DATA),a
        inc hl
        ld a,h
        cp 40h
        jr nz,t1wl
        ld a,(pg)
        inc a
        ld (pg),a
        cp 8
        jr nz,t1w
        xor a
        ld (pg),a
t1r:    call t1setr
        ld hl,0
t1rl:   call t1val
        ld c,a
        in a,(P_DATA)
        cp c
        call nz,t1err
        inc hl
        ld a,h
        cp 40h
        jr nz,t1rl
        ld a,(pg)
        inc a
        ld (pg),a
        cp 8
        jr nz,t1r

        ; ---- 2: address, then R#14, then data ----------------------------
        ld a,0                  ; R#14 = 0
        ld e,14
        call wreg
        ld a,0A0h               ; write address 20A0h
        out (P_CTRL),a
        ld a,20h or 40h
        out (P_CTRL),a
        ld a,2                  ; R#14 = 2 after the address
        ld e,14
        call wreg
        ld b,16
        ld a,0C0h
t2w:    out (P_DATA),a
        inc a
        djnz t2w
        ld a,2                  ; read back A0A0h
        ld e,14
        call wreg
        ld a,0A0h
        out (P_CTRL),a
        ld a,20h
        out (P_CTRL),a
        ld b,16
        ld c,0C0h
t2r:    in a,(P_DATA)
        cp c
        jr z,t2ok
        ld hl,rslt2
        inc (hl)
        ld (rslt2+1),a           ; last wrong byte
t2ok:   inc c
        djnz t2r

        ; ---- 3: SCREEN 5 commands ----------------------------------------
        ld hl,scr5
        call wregs
        ; page 0 and page 1 cleared: HMMV (0,0) 256 x 512 colour 00h
        ld hl,c_clr
        call cmd
        ; HMMV page 1 (16,300) 32 x 8 colour 5Ah
        ld hl,c_hmmv
        call cmd
        ; HMMC page 1 (0,488) 8 x 8: first byte in R#44, the rest via 9Bh
        ld hl,c_hmmc
        ld a,(hdata)
        ld (c_hmmc+12),a
        call cmd_nowait
        ld a,44 or 80h          ; R#17 = ACh: R#44, no auto increment
        ld e,17
        call wreg
        ld hl,hdata+1
        ld b,31
t3h:    ld a,(hl)
        out (P_IND),a
        inc hl
        if defined FASTHMMC
        nop                     ; no pause: OUT every ~20 T (faster than the game)
        else
        push bc
        ld b,20                 ; a pause between bytes (the game: ~8.7 us)
t3d:    djnz t3d
        pop bc
        endif
        djnz t3h
        call wait_ce
        ; HMMM page 1 (16,300) 32 x 8 -> page 0 (64,40)
        ld hl,c_hmmm
        call cmd
        ; HMMV page 0 (100,100) 16 x 8 colour 33h, then LMMM TIMP from the
        ; HMMC block (0,488) 8 x 8 onto (100,100)
        ld hl,c_back
        call cmd
        ld hl,c_lmmm
        call cmd
        ; PSET (11,20) colour 7
        ld hl,c_pset
        call cmd

        ; check HMMC block in page 1: y 488..495, x 0..7 (4 bytes a line)
        ld de,488
        ld hl,hdata
        ld c,8
ck1:    push bc
        push de
        push hl
        ld bc,0                 ; x = 0
        call rdaddr             ; read address of (0, DE)
        pop hl
        ld b,4
ck1b:   in a,(P_DATA)
        cp (hl)
        call nz,e_hmmc
        inc hl
        djnz ck1b
        pop de
        inc de
        pop bc
        dec c
        jr nz,ck1
        ; check HMMM copy in page 0: y 40..47, x 62..97 (18 bytes a line):
        ; 00 at 62-63, 5A at 64-95, 00 at 96-97
        ld de,40
        ld c,8
ck2:    push bc
        push de
        ld bc,62
        call rdaddr
        ld b,18
ck2b:   in a,(P_DATA)
        ld c,0
        ld e,a
        ld a,b
        cp 18
        jr z,ck2c               ; first byte: x 62-63
        cp 1
        jr z,ck2c               ; last byte: x 96-97
        ld c,5Ah
ck2c:   ld a,e
        cp c
        call nz,e_hmmm
        djnz ck2b
        pop de
        inc de
        pop bc
        dec c
        jr nz,ck2
        ; check LMMM TIMP: (100,100) 8 x 8; a source pixel 0 keeps the 3
        ld de,100
        ld hl,hdata
        ld c,8
ck3:    push bc
        push de
        push hl
        ld bc,100
        call rdaddr
        pop hl
        ld b,4
ck3b:   ld a,(hl)
        call timp               ; expected byte in A
        ld c,a
        in a,(P_DATA)
        cp c
        call nz,e_lmmm
        inc hl
        djnz ck3b
        pop de
        inc de
        pop bc
        dec c
        jr nz,ck3
        ; check PSET: (11,20) is the low nibble of byte (10,20): 07h
        ld de,20
        ld bc,10
        call rdaddr
        in a,(P_DATA)
        cp 07h
        jr z,ck4
        ld hl,rslt3+3
        inc (hl)
ck4:

        ; ---- back to text and print ----------------------------------
        ld iy,(EXPTBL-1)
        ld ix,INITXT
        call CALSLT
        ei
        ld de,m_title
        call puts
        ld de,m_t1
        call puts
        ld hl,(rslt1)
        call pres
        ld de,m_t2
        call puts
        ld a,(rslt2)
        ld l,a
        ld h,0
        call pres
        ld de,m_t3a
        call puts
        ld a,(rslt3)
        ld l,a
        ld h,0
        call pres
        ld de,m_t3b
        call puts
        ld a,(rslt3+1)
        ld l,a
        ld h,0
        call pres
        ld de,m_t3c
        call puts
        ld a,(rslt3+2)
        ld l,a
        ld h,0
        call pres
        ld de,m_t3d
        call puts
        ld a,(rslt3+3)
        ld l,a
        ld h,0
        call pres
        ret

; ---- test 1 helpers -----------------------------------------------------
t1setw: ld a,(pg)
        ld e,14
        call wreg
        xor a
        out (P_CTRL),a
        ld a,40h
        out (P_CTRL),a
        ret
t1setr: ld a,(pg)
        ld e,14
        call wreg
        xor a
        out (P_CTRL),a
        out (P_CTRL),a
        ret
; value of offset HL in block (pg): l xor h xor pg * 35h
t1val:  ld a,(pg)
        ld c,a
        add a,a
        add a,a
        add a,c
        add a,a
        add a,a
        add a,c                 ; * 21
        add a,a
        add a,c                 ; * 43
        xor l
        xor h
        ret
t1err:  push hl
        ld hl,(rslt1)
        inc hl
        ld a,h
        or l
        jr nz,t1e1
        dec hl
t1e1:   ld (rslt1),hl
        pop hl
        ret

; ---- VDP -------------------------------------------------------------
; A to register E
wreg:   out (P_CTRL),a
        ld a,e
        or 80h
        out (P_CTRL),a
        ret
; (HL): register, value pairs, FFh ends
wregs:  ld a,(hl)
        cp 0FFh
        ret z
        ld e,a
        inc hl
        ld a,(hl)
        inc hl
        call wreg
        jr wregs
; command block at HL: R#32-R#46 (15 bytes), then wait for CE = 0
cmd:    call cmd_nowait
wait_ce:
        ld a,2
        ld e,15
        call wreg
wce1:   in a,(P_CTRL)
        rrca
        jr c,wce1
        xor a
        ld e,15
        jp wreg
cmd_nowait:
        ld a,32                 ; R#17 = 32, auto increment
        ld e,17
        call wreg
        ld bc,15 * 256 + P_IND
        otir
        ret
; VRAM read address of SCREEN 5 point (C = x < 256, DE = y < 512):
; A = y * 128 + x / 2; R#14 = A16-A14 = y >> 7, low byte (y & 1) << 7 | x / 2,
; high byte (y & 7Fh) >> 1
rdaddr: ld a,c
        srl a
        ld c,a                  ; x / 2
        ld a,e
        and 1
        rrca
        or c
        ld c,a                  ; low byte
        ld a,e
        and 7Eh
        rrca
        ld b,a                  ; high byte (read)
        ld a,e
        rlca
        and 1
        ld l,a
        ld a,d
        add a,a
        or l                    ; y >> 7
        ld e,14
        call wreg
        ld a,c
        out (P_CTRL),a
        ld a,b
        out (P_CTRL),a
        ret
; expected LMMM TIMP byte: source byte A over background 33h
timp:   push bc
        ld b,a
        and 0F0h
        jr nz,tp1
        ld a,30h
tp1:    ld c,a
        ld a,b
        and 0Fh
        jr nz,tp2
        ld a,03h
tp2:    or c
        pop bc
        ret
e_hmmc: push hl
        ld hl,rslt3
        inc (hl)
        pop hl
        ret
e_hmmm: push hl
        ld hl,rslt3+1
        inc (hl)
        pop hl
        ret
e_lmmm: push hl
        ld hl,rslt3+2
        inc (hl)
        pop hl
        ret

; ---- output ------------------------------------------------------------
pres:   ld a,h
        or l
        ld de,m_ok
        jr z,puts
        ld de,m_fail
        call puts
        call pdec
        ld de,m_crlf
puts:   push hl
        ld c,09h
        call BDOS
        pop hl
        ret
pdec:   ld b,0
        ld de,-10000
        call pd1
        ld de,-1000
        call pd1
        ld de,-100
        call pd1
        ld de,-10
        call pd1
        ld a,l
        add a,'0'
        jr putc
pd1:    ld a,'0'-1
pd2:    inc a
        add hl,de
        jr c,pd2
        sbc hl,de
        cp '0'
        jr nz,pd3
        bit 0,b
        ret z
pd3:    ld b,1
putc:   push bc
        push de
        push hl
        ld e,a
        ld c,02h
        call BDOS
        pop hl
        pop de
        pop bc
        ret

; ---- data -------------------------------------------------------------
        if defined DISPON
; SCREEN 5, display on (R#1 60h), sprites on (R#8 08h), sprite tables at
; 7600h / 7800h (as the BIOS), page 0, 212 lines
scr5:   db 0,06h, 1,60h, 2,1Fh, 5,0EFh, 11,0, 6,0Fh, 8,08h, 9,80h, 23,0, 0FFh
        else
; SCREEN 5, display off, page 0, 212 lines, VRAM 128 KB (R#8 VR)
scr5:   db 0,06h, 1,20h, 2,1Fh, 8,08h, 9,80h, 23,0, 0FFh
        endif

;          SX     SY      DX     DY      NX     NY      CLR ARG CMD
c_clr:  dw 0,     0,      0,     0,      256,   512
        db 00h, 0, 0C0h
c_hmmv: dw 0,     0,      16,    300,    32,    8
        db 5Ah, 0, 0C0h
c_hmmc: dw 0,     0,      0,     488,    8,     8
        db 0,   0, 0F0h
c_hmmm: dw 16,    300,    64,    40,     32,    8
        db 0,   0, 0D0h
c_back: dw 0,     0,      100,   100,    16,    8
        db 33h, 0, 0C0h
c_lmmm: dw 0,     488,    100,   100,    8,     8
        db 0,   0, 98h
c_pset: dw 0,     0,      11,    20,     0,     0
        db 07h, 0, 50h

; HMMC data: 8 lines of 4 bytes, pixels with zeros in them for TIMP
hdata:  db 12h,30h,04h,56h, 70h,08h,9Ah,0B0h, 0Ch,0DEh,00h,0F1h, 23h,04h,50h,67h
        db 89h,0A0h,0Bh,0CDh, 0E0h,0Fh,12h,30h, 45h,06h,78h,09h, 0A0h,0BCh,0Dh,0EFh

m_title: db 13,10,"VDPTEST (Zanac EX checks)",13,10,'$'
m_t1:   db "1 VRAM 128 KB with R#14 : $"
m_t2:   db "2 addr, R#14, data      : $"
m_t3a:  db "3 HMMC via 9Bh (page 1) : $"
m_t3b:  db "  HMMM page 1 -> 0      : $"
m_t3c:  db "  LMMM TIMP             : $"
m_t3d:  db "  PSET                  : $"
m_ok:   db "OK",13,10,'$'
m_fail: db "FAIL $"
m_crlf: db 13,10,'$'

pg:     db 0
rslt:
rslt1:   dw 0
        db 0
rslt2:   db 0,0
rslt3:   db 0,0,0,0
RSLTLEN  equ $-rslt
