; V99CMD.COM: V9990 (GFX9000) P1 LMMV / write mask test for ZEMMIX, MSX-DOS 2 / Nextor.
; Assemble: pasmo V99CMD.ASM V99CMD.COM
;
; Ghosts'n Goblins (GFX9000) clears tile 0 of layer B for its second screen
; with an LMMV in P1: DX 512, DY 0, 8 x 8, colour 0, LOP 0Ch, WM FF00h.
; Each case below fills tile 0 of layer A (VRAM 00000h, rows of 128 bytes)
; and of layer B (40000h) with 1Bh, runs the LMMV, waits for CE = 0 and
; prints the first 4 bytes of the 8 rows of both tiles.
;   case DX   WM     expected
;   1    512  FF00h  A 1B..., B 00...   (the GNG one)
;   2    512  FFFFh  A 1B..., B 00...
;   3    0    00FFh  A 00..., B 1B...
;   4    0    FFFFh  A 00..., B 1B...
;   5    512  00FFh  A 1B..., B 1B...   (masked out)

BDOS    equ 5
P_VRAM  equ 60h                 ; P#0 VRAM data
P_RDATA equ 63h                 ; P#3 register data
P_RSEL  equ 64h                 ; P#4 register select
P_STAT  equ 65h                 ; P#5 status (bit 0 CE)
P_SYS   equ 67h                 ; P#7 system control

        org 100h

start:  ld de,m_title
        call puts
        xor a
        out (P_SYS),a
        ld hl,initregs
init1:  ld a,(hl)
        cp 0FFh
        jr z,init2
        out (P_RSEL),a
        inc hl
        ld a,(hl)
        out (P_RDATA),a
        inc hl
        jr init1
init2:  ld hl,cases
        ld b,5
case_l: push bc
        ld a,6
        sub b
        ld (ncase),a
        ld e,(hl)               ; DX
        inc hl
        ld d,(hl)
        inc hl
        ld (c_dx),de
        ld e,(hl)               ; WM
        inc hl
        ld d,(hl)
        inc hl
        ld (c_wm),de
        push hl

        ld a,00h                ; fill both tiles with 1Bh
        call fill
        ld a,04h
        call fill

        ld a,36                 ; R#36-R#52, auto increment
        out (P_RSEL),a
        ld hl,c_dx
        ld bc,17*256+P_RDATA
        otir
wce:    in a,(P_STAT)
        rrca
        jr c,wce

        ld de,m_case
        call puts
        ld a,(ncase)
        add a,'0'
        call putc
        ld de,m_dx
        call puts
        ld hl,(c_dx)
        ld a,h
        call phex
        ld a,l
        call phex
        ld de,m_wm
        call puts
        ld hl,(c_wm)
        ld a,h
        call phex
        ld a,l
        call phex
        ld de,m_crlf
        call puts
        ld de,m_a
        call puts
        ld a,00h
        call show
        ld de,m_b
        call puts
        ld a,04h
        call show

        pop hl
        pop bc
        dec b
        jp nz,case_l
        ret

; ---- fill tile 0 rows of the layer at A (bits 18-16) with 1Bh ---------
fill:   ld (f_hi),a
        ld c,0                  ; row offset low (row * 128)
        ld e,0                  ; row offset mid
        ld b,8
fil1:   push bc
        xor a                   ; R#0-R#2
        out (P_RSEL),a
        ld a,c
        out (P_RDATA),a
        ld a,e
        out (P_RDATA),a
        ld a,(f_hi)
        out (P_RDATA),a
        ld a,1Bh
        out (P_VRAM),a
        out (P_VRAM),a
        out (P_VRAM),a
        out (P_VRAM),a
        pop bc
        ld a,c
        add a,80h
        ld c,a
        jr nc,fil2
        inc e
fil2:   djnz fil1
        ret

; ---- print the 4 first bytes of the 8 rows of tile 0 ------------------
show:   ld (f_hi),a
        ld c,0
        ld e,0
        ld b,8
sho1:   push bc
        push de
        ld a,3                  ; R#3-R#5
        out (P_RSEL),a
        ld a,c
        out (P_RDATA),a
        ld a,e
        out (P_RDATA),a
        ld a,(f_hi)
        out (P_RDATA),a
        ld b,4
sho2:   in a,(P_VRAM)
        call phex
        djnz sho2
        ld a,' '
        call putc
        pop de
        pop bc
        ld a,c
        add a,80h
        ld c,a
        jr nc,sho3
        inc e
sho3:   djnz sho1
        ld de,m_crlf
        jp puts

; ---- output -----------------------------------------------------------
phex:   push af
        rrca
        rrca
        rrca
        rrca
        call phex1
        pop af
phex1:  and 0Fh
        add a,'0'
        cp '9'+1
        jr c,putc
        add a,'A'-'9'-1
putc:   push af
        push bc
        push de
        push hl
        ld e,a
        ld c,02h
        call BDOS
        pop hl
        pop de
        pop bc
        pop af
        ret

puts:   push af
        push bc
        push hl
        ld c,09h
        call BDOS
        pop hl
        pop bc
        pop af
        ret

; ---- data -------------------------------------------------------------
initregs:
        db 8,02h                ; display off, VRAM 512 KB
        db 9,00h                ; no interrupts
        db 6,05h                ; P1 (as GNG)
        db 7,00h
        db 0FFh

; DX, WM
cases:  dw 512,0FF00h
        dw 512,0FFFFh
        dw 0,000FFh
        dw 0,0FFFFh
        dw 512,000FFh

; R#36-R#52
c_dx:   dw 0                    ; R#36-R#37 DX
c_dy:   dw 0                    ; R#38-R#39 DY
c_nx:   dw 8                    ; R#40-R#41 NX
c_ny:   dw 8                    ; R#42-R#43 NY
c_arg:  db 0                    ; R#44 ARG
c_lop:  db 0Ch                  ; R#45 LOP: copy
c_wm:   dw 0                    ; R#46-R#47 WM
c_fc:   dw 0                    ; R#48-R#49 FC
c_bc:   dw 0                    ; R#50-R#51
c_op:   db 20h                  ; R#52 LMMV

ncase:  db 0
f_hi:   db 0

m_title: db "V9990 P1 LMMV / write mask test (GNG screen 2)",13,10,'$'
m_case:  db "Case $"
m_dx:    db "  DX $"
m_wm:    db "  WM $"
m_a:     db " A $"
m_b:     db " B $"
m_crlf:  db 13,10,'$'
