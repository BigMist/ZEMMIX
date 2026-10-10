; VDPDISP.COM: SCREEN 5 page display test for ZEMMIX (V9968), MSX-DOS.
; Assemble: pasmo VDPDISP.ASM VDPDISP.COM
;
; Fills the four SCREEN 5 pages with HMMV and shows them, about 3 s each:
;   page 0  16 vertical colour bars (colour = x / 16)
;   page 1  16 horizontal bands (colour = y / 16)
;   page 2  chessboard of 32 x 32 squares, colours 6 and 15
;   page 3  colour 4 with a white frame (lines 0, 211, columns 0, 255)
; then page 0 again with R#23 (vertical scroll) stepping 0..255, and back
; to the text screen.  A correct VDP shows only that page's pattern each
; time, and while scrolling the bars stay vertical bars.

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
        ; page 2: chessboard 8 x 8 squares of 32
        xor a
        ld (col),a              ; square number 0..63
p2:     ld a,(col)
        and 7
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl               ; x = (n & 7) * 32
        ld (b_dx),hl
        ld a,(col)
        rrca
        rrca
        rrca
        and 7
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,512
        add hl,de               ; y = 512 + (n >> 3) * 32
        ld (b_dy),hl
        ld hl,32
        ld (b_nx),hl
        ld (b_ny),hl
        ld a,(col)
        ld c,a
        rrca
        rrca
        rrca
        xor c
        and 1
        ld a,66h
        jr z,p2c
        ld a,0FFh
p2c:    ld (b_clr),a
        call hmmv
        ld a,(col)
        inc a
        ld (col),a
        cp 64
        jr nz,p2
        ; page 3: colour 4, white frame
        ld hl,0
        ld (b_dx),hl
        ld hl,768
        ld (b_dy),hl
        ld hl,256
        ld (b_nx),hl
        ld (b_ny),hl
        ld a,44h
        ld (b_clr),a
        call hmmv
        ld a,0FFh
        ld (b_clr),a
        ld hl,768               ; top line
        ld (b_dy),hl
        ld hl,1
        ld (b_ny),hl
        call hmmv
        ld hl,768 + 211         ; line 211
        ld (b_dy),hl
        call hmmv
        ld hl,768
        ld (b_dy),hl
        ld hl,212
        ld (b_ny),hl
        ld hl,2
        ld (b_nx),hl            ; columns 0-1
        call hmmv
        ld hl,254
        ld (b_dx),hl            ; columns 254-255
        call hmmv

        ; show pages 0..3
        ld a,60h                ; R#1: display on
        ld e,1
        call wreg
        ld a,1Fh                ; page 0
        call show
        ld a,3Fh                ; page 1
        call show
        ld a,5Fh                ; page 2
        call show
        ld a,7Fh                ; page 3
        call show
        ld a,1Fh
        ld e,2
        call wreg
        ; R#23 0..255, two frames each
        xor a
        ld (col),a
sc:     ld a,(col)
        ld e,23
        di
        call wreg
        ei
        ld b,2
        call frames
        ld a,(col)
        inc a
        ld (col),a
        jr nz,sc
        di
        xor a
        ld e,23
        call wreg
        ld iy,(EXPTBL-1)
        ld ix,INITXT
        call CALSLT
        ei
        ret

; R#2 = A, then wait 180 frames (3 s)
show:   di
        ld e,2
        call wreg
        ei
        ld b,180
frames: ld hl,JIFFY
        ld a,(hl)
fr1:    cp (hl)
        jr z,fr1
        djnz frames
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
scr5:   db 0,06h, 1,20h, 2,1Fh, 7,00h, 8,0Ah, 9,80h, 23,0, 0FFh

col:    db 0
b_dx:   dw 0                    ; R#36-R#37
b_dy:   dw 0                    ; R#38-R#39
b_nx:   dw 0                    ; R#40-R#41
b_ny:   dw 0                    ; R#42-R#43
b_clr:  db 0                    ; R#44
b_arg:  db 0                    ; R#45
b_cmd:  db 0C0h                 ; R#46 HMMV
