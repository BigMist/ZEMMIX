; VDPHAM2.COM: R#13 / R#23 sequence test (Zanac EX intro)
; (built from VDPHAM.ASM) hammer test for the ZEMMIX VDP (V9968), MSX-DOS.
; Assemble: pasmo VDPHAM2.ASM VDPHAM2.COM
; Phase A: R#13 = 3Eh, R#13 = 00h, 5 s.  Phase B: R#23 30h..FFh, 00h at one
; step a frame, 5 s.  The vertical bars of page 0 must stay (moving up in B).
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
        ; phase A: R#13 = 3Eh then 00h (the game, 4.93 s), then 5 s still
        di
        ld a,3Eh
        ld e,13
        call wreg
        xor a
        ld e,13
        call wreg
        ei
        call start5
pa:     call left5
        jr nz,pa
        ; phase B: R#23 from 30h to FFh and 00h, one step a frame, then 5 s
        ld a,30h
        ld (sc23),a
pb:     ld a,(sc23)
        di
        ld e,23
        call wreg
        ei
        ld hl,JIFFY
        ld a,(hl)
pb1:    cp (hl)
        jr z,pb1
        ld a,(sc23)
        inc a
        ld (sc23),a
        jr nz,pb
        di
        xor a
        ld e,23
        call wreg
        ei
        call start5
pb2:    call left5
        jr nz,pb2
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
