; V99MODE.COM: V9990 (GFX9000) bitmap mode test for ZEMMIX, MSX-DOS.
; Assemble: pasmo V99MODE.ASM V99MODE.COM
;
; The same 16 colour picture (image 1024 wide, 512 lines) in the bitmap
; modes one after the other, a key for the next one:
;   B1 256x212, B3 512x212, B7 1024x212, B0 256x240, B2 384x240, B4 768x240
;   B5 640x400 (25 kHz), B6 640x480 (31 kHz), each with R#6 DCKM 2 (the
;   table of 8.3 of the Application Manual) and DCKM 3 (its sample
;   software), name "B5 640m" / "B6 640m" for the latter
; (R#6 DCKM 0 / 1 / 2, P#7 MCS 0: B1 / B3 / B7, MCS 1: B0 / B2 / B4;
; R#7 HSCN: B5, HSCN + C25M: B6).  The palette is loaded at 0-15 and
; 32-47: the odd pixels of B4 / B7 / B5 / B6 take colour + 32.
; Picture: a white grid every 8 pixels / lines; inside the cells, left half
; columns 1 on / 1 off (blue), right half lines 1 on / 1 off (red); yellow
; bars in the top left cell.  The mode name (B1 ... B4) in big yellow
; letters at the top left, and on the MSX screen.
; On a correct output every column and line is there: a lost column breaks
; the left half, a lost line the right half.

BDOS    equ 5
P_VRAM  equ 60h
P_PAL   equ 61h
P_RDATA equ 63h
P_RSEL  equ 64h
P_SYS   equ 67h

        org 100h

start:  ld de,m_title
        call puts
        xor a
        out (P_SYS),a
        ld a,8                  ; display off while drawing
        out (P_RSEL),a
        ld a,02h
        out (P_RDATA),a
        ; palette: 0 black, 1 blue, 2 red, 3 yellow, 15 white
        ld a,14                 ; R#14 palette pointer = 0
        out (P_RSEL),a
        xor a
        out (P_RDATA),a
        ld hl,pal               ; 0-15, 16-31 black, 32-47 the same
        ld b,16*3
        ld c,P_PAL
        otir
        ld b,16*3
        xor a
pal1:   out (P_PAL),a
        djnz pal1
        ld hl,pal
        ld b,16*3
        otir
        ; R#13 palette control 0, R#15 backdrop 0, R#16 adjust 0, scroll 0
        ld hl,init
ini1:   ld a,(hl)
        cp 0FFh
        jr z,ini2
        out (P_RSEL),a
        inc hl
        ld a,(hl)
        out (P_RDATA),a
        inc hl
        jr ini1
ini2:   ld a,6                  ; bitmap mode first: the CPU addresses of
        out (P_RSEL),a          ; the VRAM depend on it (bitmap: even and
        ld a,89h                ; odd bytes in the two halves)
        out (P_RDATA),a
        ; picture: 512 lines of 512 bytes (1024 pixels, 4 bpp) from VRAM 0
        xor a                   ; R#0-R#2 = 0
        out (P_RSEL),a
        out (P_RDATA),a
        out (P_RDATA),a
        out (P_RDATA),a
        ld hl,0                 ; y
pic1:   ld (y),hl
        call mkline
        ld hl,line
        ld c,P_VRAM
        ld b,0
        otir                    ; 256 bytes
        otir                    ; 512
        ld hl,(y)
        inc hl
        ld a,h
        cp 2
        jr nz,pic1              ; 512 lines

        ld hl,modes
        ld b,10
mod1:   push bc
        push hl
        push hl
        inc hl                  ; the digit of the name: "Bn ..."
        inc hl
        inc hl
        inc hl
        ld a,(hl)
        call label
        pop hl
        ld a,(hl)               ; R#6
        ld e,a
        inc hl
        ld a,(hl)               ; MCS
        out (P_SYS),a
        inc hl
        ld a,6                  ; R#6, R#7
        out (P_RSEL),a
        ld a,e
        out (P_RDATA),a
        ld a,7
        out (P_RSEL),a
        ld a,(hl)
        out (P_RDATA),a
        ld a,8                  ; display on
        out (P_RSEL),a
        ld a,82h
        out (P_RDATA),a
        inc hl
        ex de,hl                ; DE -> name
        call puts
        ld c,08h                ; wait for a key
        call BDOS
        pop hl
        ld de,13                ; next entry
        add hl,de
        pop bc
        djnz mod1
        ld a,7                  ; R#7 0 (no high scan), display off, MCS 0
        out (P_RSEL),a
        xor a
        out (P_RDATA),a
        ld a,8
        out (P_RSEL),a
        xor a
        out (P_RDATA),a
        out (P_SYS),a
        ld de,m_end
        jp puts

; ---- one line of the picture in 'line': pixel (x, y), 2 per byte ------
mkline: ld ix,line
        ld de,0                 ; x
mk1:    call pixel
        rlca
        rlca
        rlca
        rlca
        ld c,a
        inc de
        call pixel
        or c
        ld (ix+0),a
        inc ix
        inc de
        ld a,d
        cp 4                    ; 1024 pixels
        jr nz,mk1
        ret
; colour of (DE, y) in A
pixel:  ld a,e                  ; grid: x and 7 = 0 or y and 7 = 0
        and 7
        jr z,px_w
        ld a,(y)
        and 7
        jr z,px_w
        ld a,(y+1)              ; mode mark: lines 2-5, x 2..2+2*n
        or a
        jr nz,px1
        ld a,(y)
        cp 2
        jr c,px1
        cp 6
        jr nc,px1
        ld a,d
        or a
        jr nz,px1
        ld a,e
        cp 2
        jr c,px1
        cp 16
        jr nc,px1
        and 1
        jr nz,px1
        ld a,3
        ret
px1:    ld a,d                  ; left half (x < 512): columns
        cp 2
        jr nc,px2
        ld a,e
        and 1
        ret z                   ; 0
        ld a,1
        ret
px2:    ld a,(y)                ; right half: lines
        and 1
        ret z
        ld a,2
        ret
px_w:   ld a,15
        ret

; ---- the name "Bn" in big yellow letters at the top left (A = '0'-'7') --
; a 3 x 5 font scaled x4: 'B' then the digit, 16 pixels a letter (12 + 4),
; lines 8-31 (a black box of 24 lines), pixels 8-71 (VRAM bytes 4-35)
label:  sub '0'                 ; DE -> 5 rows of the digit
        ld l,a
        ld h,0
        ld e,l
        ld d,h
        add hl,hl
        add hl,hl
        add hl,de               ; * 5
        ld de,font
        add hl,de
        ld (lb_dig),hl
        xor a
        ld (lb_row),a
lb1:    xor a                   ; VRAM address = (8 + row) * 512 + 4
        out (P_RSEL),a          ; R#0-R#2
        ld a,4
        out (P_RDATA),a         ; bits 7-0 = 4
        ld a,(lb_row)
        add a,8
        add a,a
        out (P_RDATA),a         ; bits 15-8 = (row + 8) * 2 (row + 8 < 128)
        xor a
        out (P_RDATA),a         ; bits 18-16 = 0
        ; the glyph row: (row - 2) / 4 when 2 <= row < 22, else none
        ld a,(lb_row)
        sub 2
        jr c,lb_blank
        cp 20
        jr nc,lb_blank
        srl a
        srl a
        ld e,a
        ld d,0
        ld hl,font+50           ; 'B' after the 10 digits
        add hl,de
        ld b,(hl)               ; B = 'B' row bits (bit 2 = left)
        ld hl,(lb_dig)
        add hl,de
        ld c,(hl)               ; C = digit row bits
        ld a,b
        call lb_glyph           ; 8 bytes: 16 pixels
        ld a,c
        call lb_glyph
        jr lb2
lb_blank:
        ld b,16
        xor a
lb_b1:  out (P_VRAM),a
        djnz lb_b1
lb2:    ld a,(lb_row)
        inc a
        ld (lb_row),a
        cp 24
        jr nz,lb1
        ret
; 16 pixels (8 bytes) of a letter row: A = 3 bits, each 4 pixels of colour 3
lb_glyph:
        ld e,a
        ld b,5
lg1:    rl e                    ; bit 2 first: the 3 bits to bits 7-5
        djnz lg1
        ld b,3
lg2:    rl e                    ; next bit to carry
        ld a,0
        jr nc,lg3
        ld a,33h
lg3:    out (P_VRAM),a          ; 4 pixels = 2 bytes
        out (P_VRAM),a
        djnz lg2
        xor a                   ; 4 pixels gap
        out (P_VRAM),a
        out (P_VRAM),a
        ret
puts:   ld c,09h
        jp BDOS

; palette: R, G, B (5 bits) for colours 0-15
pal:    db 0,0,0, 0,0,31, 31,0,0, 31,31,0
        db 0,0,0, 0,0,0, 0,0,0, 0,0,0
        db 0,0,0, 0,0,0, 0,0,0, 0,0,0
        db 0,0,0, 0,0,0, 0,0,0, 31,31,31
; register, value; FFh ends
init:   db 7,00h, 9,00h, 13,00h, 15,00h, 16,00h
        db 17,00h, 18,00h, 19,00h, 20,00h, 21,00h, 22,00h, 23,00h, 24,00h
        db 0FFh
; R#6, P#7, R#7, name (10 bytes, '$'); the digit of the name is byte 4
modes:  db 89h,0,0,   "B1 256 ",13,10,'$'
        db 99h,0,0,   "B3 512 ",13,10,'$'
        db 0A9h,0,0,  "B7 1024",13,10,'$'
        db 89h,1,0,   "B0 256o",13,10,'$'
        db 99h,1,0,   "B2 384o",13,10,'$'
        db 0A9h,1,0,  "B4 768o",13,10,'$'
        db 0A9h,0,01h,"B5 640 ",13,10,'$'
        db 0A9h,0,41h,"B6 640 ",13,10,'$'
        db 0B9h,0,01h,"B5 640m",13,10,'$'
        db 0B9h,0,41h,"B6 640m",13,10,'$'
m_title: db "V9990 bitmap modes: a key for the next one.",13,10,'$'
m_end:   db "Done.",13,10,'$'
; 3 x 5 font, bit 2 = left: digits 0-9 then 'B'
font:   db 7,5,5,5,7, 2,6,2,2,7, 7,1,7,4,7, 7,1,7,1,7, 5,5,7,1,1
        db 7,4,7,1,7, 7,4,7,5,7, 7,1,1,1,1, 7,5,7,5,7, 7,5,7,1,7
        db 6,5,6,5,6
lb_dig: dw 0
lb_row: db 0
y:      dw 0
line:   ds 512
