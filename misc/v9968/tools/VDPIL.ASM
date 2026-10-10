; VDPIL.COM: V9938 / V9958 interlace test for ZEMMIX (R#9 IL / EO), MSX-DOS.
; Assemble: pasmo VDPIL.ASM VDPIL.COM
;
; SCREEN 5 with a 424-line picture split over two pages: page 0 has the even
; lines of the picture, page 1 the odd ones.  The test drawing:
;   left half   a red line on page 0 and a green line on page 1 at the same
;               page line, every 8 page lines: in the picture the green line
;               is right BELOW the red one (above: the fields are swapped)
;   right half  45 degree diagonals split over both pages: smooth in the
;               picture (zigzag / steps: fields swapped or not offset)
; Phases of about 8 s:
;   1  R#9 IL + EO (R#2 page 1): the 424-line picture, both pages
;   2  R#9 IL only: page 1 in both fields, must stand still (no jumping)
;   3  no interlace: page 1 only, the reference
; then back to the text screen.

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
        ; both pages colour 4 (dark blue)
        ld hl,0
        ld (b_dx),hl
        ld (b_dy),hl
        ld hl,256
        ld (b_nx),hl
        ld hl,512
        ld (b_ny),hl
        ld a,44h
        ld (b_clr),a
        call hmmv
        ; left half: red on page 0, green on page 1, every 8 lines
        ld hl,128
        ld (b_nx),hl
        ld hl,1
        ld (b_ny),hl
        ld hl,0
        ld (b_dx),hl
        xor a
        ld (lny),a
lh:     ld a,(lny)
        ld l,a
        ld h,0
        ld (b_dy),hl
        ld a,88h                ; red (colour 8)
        ld (b_clr),a
        call hmmv
        ld a,(lny)
        ld l,a
        ld h,1                  ; + 256: page 1
        ld (b_dy),hl
        ld a,22h                ; green (colour 2)
        ld (b_clr),a
        call hmmv
        ld a,(lny)
        add a,8
        ld (lny),a
        cp 212
        jr c,lh
        ; right half: two 45 degree diagonals of the 424-line picture
        ;   picture (128 + L, L): page 0 (128 + 2m, m), page 1 (129 + 2m, m)
        ld hl,l_list
        ld b,4
ld1:    push bc
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld (l_dx),de
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld (l_dy),de
        push hl
        call line
        pop hl
        pop bc
        djnz ld1

        ; phase 1: IL + EO, page 1 (alternates with page 0)
        ld a,3Fh
        ld e,2
        call wreg
        ld a,8Ch                ; LN, IL, EO
        ld e,9
        call wreg
        ld a,60h                ; display on
        ld e,1
        call wreg
        ei
        call wait8
        ; phase 2: IL only
        di
        ld a,88h
        ld e,9
        call wreg
        ei
        call wait8
        ; phase 3: no interlace
        di
        ld a,80h
        ld e,9
        call wreg
        ei
        call wait8
        di
        ld iy,(EXPTBL-1)
        ld ix,INITXT
        call CALSLT
        ei
        ret

; about 8 s (480 frames)
wait8:  ld bc,480
w8:     ld hl,JIFFY
        ld a,(hl)
w81:    cp (hl)
        jr z,w81
        dec bc
        ld a,b
        or c
        jr nz,w8
        ret

; LINE from (l_dx, l_dy), long side 126 (X), short side 63, colour 15
line:   ld a,36
        ld e,17
        call wreg
        ld hl,l_dx
        ld bc,11 * 256 + P_IND  ; R#36-R#46
        otir
        jr cewait

; HMMV with b_dx, b_dy, b_nx, b_ny, b_clr; waits for CE = 0
hmmv:   ld a,36                 ; R#17 = 36 (DX), auto increment
        ld e,17
        call wreg
        ld hl,b_dx
        ld bc,11 * 256 + P_IND  ; R#36-R#46
        otir
cewait: ld a,2
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

; diagonal starts (DX, DY): page 0 and page 1, two of each
l_list: dw 128,0, 129,256, 128,64, 129,320

lny:    db 0
b_dx:   dw 0                    ; R#36-R#37
b_dy:   dw 0                    ; R#38-R#39
b_nx:   dw 0                    ; R#40-R#41
b_ny:   dw 0                    ; R#42-R#43
b_clr:  db 0                    ; R#44
b_arg:  db 0                    ; R#45
b_cmd:  db 0C0h                 ; R#46 HMMV

l_dx:   dw 0                    ; R#36-R#37
l_dy:   dw 0                    ; R#38-R#39
l_nx:   dw 126                  ; R#40-R#41 long side
l_ny:   dw 63                   ; R#42-R#43 short side
l_clr:  db 0Fh                  ; R#44 white
l_arg:  db 00h                  ; R#45 X major, right, down
l_cmd:  db 70h                  ; R#46 LINE
