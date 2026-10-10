; VDPSPR.COM: R#13 / R#23 sequence test (Zanac EX intro)
; (built from VDPHAM.ASM) hammer test for the ZEMMIX VDP (V9968), MSX-DOS.
; Assemble: pasmo VDPSPR.ASM VDPSPR.COM
; Sprite tables at FE00h / FC00h / B000h-B800h, sprite 0 Y = D8h (end of list),
; sprites 1-31 visible white squares if the end is not seen; 10 s with R#6
; 16h / 17h each frame.  A V9938 / V9958 shows no sprite, only the bars.
;
; Page 0: 16 vertical colour bars, page 1: 16 horizontal bands; page 0 is
; shown and the VDP is hammered in four phases of about 5 s, as Zanac EX
; does on its title screen:
;   1  R#1 = 62h written again and again
;   2  status reads: R#15 = 2, IN 99h, R#15 = 0
;   3  address 3E00h, R#14 = 3, data D8h to 98h, R#6 = 17h (sprites off at
;      FE00h, as the game does once a frame), looped
;   4  palette writes: R#16 = 0, 32 bytes to 9Ah (the same palette)
; A correct VDP keeps showing the vertical bars all the time (sprites are off
; and the palette does not change).  Bands of page 1 in a phase point to it.

CALSLT  equ 001Ch
EXPTBL  equ 0FCC1h
INITXT  equ 006Ch
JIFFY   equ 0FC9Eh
P_CTRL  equ 99h
P_IND   equ 9Bh

        org 100h

start:  di
        ld hl,scr5
        call wregs
        ; page 0: 16 bars
        ld a,0
        ld (col),a
p0:     ld a,(col)
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl               ; x = col * 16
        ld (b_dx),hl
        ld hl,0
        ld (b_dy),hl
        ld hl,16
        ld (b_nx),hl
        ld hl,256
        ld (b_ny),hl
        ld a,(col)
        ld c,a
        add a,a
        add a,a
        add a,a
        add a,a
        or c
        ld (b_clr),a
        call hmmv
        ld a,(col)
        inc a
        ld (col),a
        cp 16
        jr nz,p0
        ; page 1: 16 bands
        xor a
        ld (col),a
p1:     ld hl,0
        ld (b_dx),hl
        ld a,(col)
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,256
        add hl,de               ; y = 256 + col * 16
        ld (b_dy),hl
        ld hl,256
        ld (b_nx),hl
        ld hl,16
        ld (b_ny),hl
        ld a,(col)
        ld c,a
        add a,a
        add a,a
        add a,a
        add a,a
        or c
        ld (b_clr),a
        call hmmv
        ld a,(col)
        inc a
        ld (col),a
        cp 16
        jr nz,p1
        ; sprites off at FE00h first (sprite mode 2 table there: R#5 / R#11)
        ld a,03h
        ld e,14
        call wreg
        xor a
        out (P_CTRL),a
        ld a,3Eh or 40h
        out (P_CTRL),a
        ld a,0D8h
        out (98h),a
        ld a,62h                ; display on, IE0, 16 x 16 sprites
        ld e,1
        call wreg
        ei
        ; sprite tables as Zanac EX: attributes FE00h, colours FC00h,
        ; patterns B000h / B800h (R#6 16h / 17h).  Sprite 0 Y = D8h (end of
        ; the list in sprite mode 2); sprites 1-31 visible if it is ignored.
        di
        ld hl,0B000h            ; patterns: 4 KB of FFh (B000h-BFFFh)
        call vwset
        ld bc,4096
spp:    ld a,0FFh
        out (98h),a
        dec bc
        ld a,b
        or c
        jr nz,spp
        ld hl,0FC00h            ; colours: 512 bytes of 0Fh (white)
        call vwset
        ld bc,512
spc:    ld a,0Fh
        out (98h),a
        dec bc
        ld a,b
        or c
        jr nz,spc
        ld hl,0FE00h            ; attributes
        call vwset
        ld a,0D8h               ; sprite 0: end of list
        out (98h),a
        xor a
        out (98h),a
        out (98h),a
        out (98h),a
        ld b,31                 ; sprites 1-31: Y = n * 6, X = n * 8
        ld c,1
spa:    ld a,c
        add a,a
        add a,c
        add a,a                 ; * 6
        out (98h),a
        ld a,c
        add a,a
        add a,a
        add a,a                 ; * 8
        out (98h),a
        ld a,c
        add a,a
        add a,a                 ; pattern n * 4
        out (98h),a
        xor a
        out (98h),a
        inc c
        djnz spa
        ei
        ; 10 s, R#6 = 16h / 17h each frame, as the game
        call start5
        ld a,16h
        ld (sc23),a
sp1:    ld hl,JIFFY
        ld a,(hl)
sp2:    cp (hl)
        jr z,sp2
        ld a,(sc23)
        xor 1
        ld (sc23),a
        di
        ld e,6
        call wreg
        ei
        call left5
        jr nz,sp1
        call start5
sp3:    ld hl,JIFFY
        ld a,(hl)
sp4:    cp (hl)
        jr z,sp4
        ld a,(sc23)
        xor 1
        ld (sc23),a
        di
        ld e,6
        call wreg
        ei
        call left5
        jr nz,sp3
        di
        ld iy,(EXPTBL-1)
        ld ix,INITXT
        call CALSLT
        ei
        ret

; 300 frames (5 s): start5 sets the end, left5 gives NZ until then
start5: ld hl,(JIFFY)
        ld de,300
        add hl,de
        ld (tend),hl
        ret
left5:  push hl
        push de
        ld hl,(JIFFY)
        ld de,(tend)
        or a
        sbc hl,de
        pop de
        pop hl
        ret

; HMMV with b_dx, b_dy, b_nx, b_ny, b_clr; waits for CE = 0
hmmv:   ld a,36                 ; R#17 = 36 (DX), auto increment
        ld e,17
        call wreg
        ld hl,b_dx
        ld bc,11 * 256 + P_IND  ; R#36-R#46
        otir
        ld a,2
        ld e,15
        call wreg
hw:     in a,(P_CTRL)
        rrca
        jr c,hw
        xor a
        ld e,15
        jp wreg

; A to register E
wreg:   out (P_CTRL),a
        ld a,e
        or 80h
        out (P_CTRL),a
        ret
wregs:  ld a,(hl)
        cp 0FFh
        ret z
        ld e,a
        inc hl
        ld a,(hl)
        inc hl
        call wreg
        jr wregs

; SCREEN 5, display off, page 0, 212 lines, VRAM 128 KB, no sprites, border 0
; SCREEN 5, display off, page 0, 212 lines, VRAM 128 KB, sprite mode 2
; tables as Zanac EX (R#5 FFh, R#11 01h: FE00h; R#6 17h)
scr5:   db 0,06h, 1,20h, 2,1Fh, 5,0FFh, 11,01h, 6,17h, 7,00h, 8,08h, 9,80h, 23,0, 0FFh

col:    db 0
b_dx:   dw 0                    ; R#36-R#37
b_dy:   dw 0                    ; R#38-R#39
b_nx:   dw 0                    ; R#40-R#41
b_ny:   dw 0                    ; R#42-R#43
b_clr:  db 0                    ; R#44
b_arg:  db 0                    ; R#45
b_cmd:  db 0C0h                 ; R#46 HMMV

tend:   dw 0
sc23:   db 0
; MSX2 default palette (0RRR0BBB, 00000GGG)
pal:    db 00h,0, 00h,0, 11h,6, 33h,7, 17h,1, 27h,3, 51h,1, 27h,6
        db 71h,1, 73h,3, 61h,6, 64h,6, 11h,4, 65h,2, 55h,5, 77h,7

; VRAM write address HL (17 bits: A16 = 0 here, R#14 = H >> 6)
vwset:  ld a,h
        rlca
        rlca
        and 3
        ld e,14
        call wreg
        ld a,l
        out (P_CTRL),a
        ld a,h
        and 3Fh
        or 40h
        out (P_CTRL),a
        ret
