; V99RDBP.COM: V9990 (GFX9000) VRAM read-back test in P1 for ZEMMIX, MSX-DOS 2 / Nextor.
; Assemble: pasmo V99RDBP.ASM V99RDBP.COM  (V99RDBK in mode P1: bytes N and N+1 in the same word)
;
; Does what the decompressor of Ghosts'n Goblins (GFX9000) does on its
; second screen: for every byte it sets the read address (P#4 = 03h, then
; R#3, R#4, R#5 through P#3), reads the source byte from P#0 and writes it
; at the write pointer through P#0, often from the byte just written
; (distance 1).  A window of 16 KB, at another VRAM address each pass:
;   A  16 KB of random bytes written through P#0 (copy kept in RAM)
;   B  from 1 KB on, each byte a literal (1 / 4) or a copy from 1 to 1024
;      bytes back (3 / 4), read and written as above; a read that is not
;      the byte expected is a read-back error (the expected one is written)
;   C  the window read back in sequence: verify errors
; Even passes with the display on, odd passes with the display off, until a
; key is pressed.  On a turbo R it runs on the Z80, as GNG (the R800 reads
; P#0 sooner after R#5 than a V9990 can give the byte: openMSX then returns
; the old read buffer; the ZEMMIX core holds the CPU with WAIT instead).  After each pass: the errors of the pass, the totals and
; the first errors (R read-back / V verify, VRAM address, expected, read,
; copy distance).

BDOS    equ 5
RDSLT   equ 000Ch
CALSLT  equ 001Ch
EXPTBL  equ 0FCC1h
CHGCPU  equ 0180h               ; turbo R BIOS
GETCPU  equ 0183h
P_VRAM  equ 60h                 ; P#0 VRAM data
P_RDATA equ 63h                 ; P#3 register data
P_RSEL  equ 64h                 ; P#4 register select (bits 7/6 = 0: auto increment)
P_SYS   equ 67h                 ; P#7 system control
SHADOW  equ 8000h               ; RAM copy of the window (offset = address and 3FFFh)
WEND    equ 0C0h                ; high byte of SHADOW + 16 KB
LIT     equ 1024                ; phase B starts here: copies reach 1024 back
NREC    equ 8                   ; errors listed per pass
RECSZ   equ 7                   ; kind, address hi / mid / lo, expected, read, distance

        org 100h

start:  ld de,m_title
        call puts
        ld a,(EXPTBL)           ; MSX version: 3 = turbo R
        ld hl,002Dh
        call RDSLT
        ei
        cp 3
        jr c,cpu1
        ld a,1
        ld (turbor),a
        ld iy,(EXPTBL-1)
        ld ix,GETCPU
        call CALSLT
        ld (oldcpu),a
        ld a,80h                ; Z80, LED
        ld iy,(EXPTBL-1)
        ld ix,CHGCPU
        call CALSLT
cpu1:
        xor a
        out (P_SYS),a           ; no reset, MCS 0 (B1)
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
init2:  ld hl,tot_rd            ; clear the totals
        ld b,end_vars-tot_rd
        xor a
clr1:   ld (hl),a
        inc hl
        djnz clr1

; ---- one pass ---------------------------------------------------------
pass_l: ld hl,0
        ld (e_rd),hl
        ld (e_vf),hl
        xor a
        ld (nrec),a
        ; base = (pass mod 31) * 16 KB + (pass * 37 and FFh)
        ld a,(pass)
pm1:    cp 31
        jr c,pm2
        sub 31
        jr pm1
pm2:    ld c,a
        srl a
        srl a
        ld (b_hi),a             ; bits 18-16
        ld a,c
        rrca
        rrca
        and 0C0h
        ld (b_mid),a            ; bits 15-14
        ld a,(pass)
        ld c,a
        add a,a
        add a,a
        add a,a
        add a,c                 ; * 9
        add a,a
        add a,a                 ; * 36
        add a,c                 ; * 37
        ld (b_lo),a

        ld a,(pass)             ; display on in even passes
        and 1
        ld a,82h                ; R#8: display on, VRAM 512 KB
        jr z,dsp1
        ld a,02h
dsp1:   ld c,a
        ld a,8
        out (P_RSEL),a
        ld a,c
        out (P_RDATA),a

        ; A: random window in RAM, then to the VRAM at base
        ld hl,SHADOW
fa1:    call rnd
        ld (hl),a
        inc hl
        ld a,h
        cp WEND
        jr nz,fa1
        ld hl,0
        call setw
        ld hl,SHADOW
fa2:    ld bc,P_VRAM            ; B = 0: 256 bytes
        otir
        ld a,h
        cp WEND
        jr nz,fa2

        ; B: the decompressor
        ld hl,LIT
        call setw
        ld hl,SHADOW+LIT
pb1:    call rnd
        and 3
        jr nz,pb_cp
        call rnd                ; literal
        ld (hl),a
        out (P_VRAM),a
        jr pb_nx
pb_cp:  call rnd                ; copy from HL - d
        and 15
        add a,a
        ld e,a
        ld d,0
        push hl
        ld hl,dtab
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (dist),de
        pop hl
        push hl
        or a
        sbc hl,de               ; HL -> source in RAM
        ld a,(hl)
        ld (expv),a
        call addr               ; s_hi / s_mid / s_lo = VRAM address of HL
        ld a,3                  ; as GNG: P#4 = 03h, R#3, R#4, R#5, P#0 in, P#0 out
        out (P_RSEL),a
        ld a,(s_lo)
        out (P_RDATA),a
        ld a,(s_mid)
        out (P_RDATA),a
        ld a,(s_hi)
        out (P_RDATA),a
        in a,(P_VRAM)
        ld (gotv),a
        ld c,a
        ld a,(expv)
        cp c
        ld c,'R'
        call nz,error
        pop hl
        ld a,(expv)
        ld (hl),a
        out (P_VRAM),a
pb_nx:  inc hl
        ld a,h
        cp WEND
        jr nz,pb1

        ; C: verify the window
        ld a,3
        out (P_RSEL),a
        ld a,(b_lo)
        out (P_RDATA),a
        ld a,(b_mid)
        out (P_RDATA),a
        ld a,(b_hi)
        out (P_RDATA),a
        ld hl,0
        ld (dist),hl
        ld hl,SHADOW
pc1:    in a,(P_VRAM)
        cp (hl)
        jr z,pc2
        ld (gotv),a
        ld a,(hl)
        ld (expv),a
        push hl
        call addr
        ld c,'V'
        call error
        pop hl
pc2:    inc hl
        ld a,h
        cp WEND
        jr nz,pc1

; ---- report -----------------------------------------------------------
        ld hl,(e_rd)
        ld de,tot_rd
        call addsat
        ld hl,(e_vf)
        ld de,tot_vf
        call addsat

        ld de,m_pass
        call puts
        ld hl,(pass)
        call pdec
        ld de,m_at
        call puts
        ld a,(b_hi)
        call phex1
        ld a,(b_mid)
        call phex
        ld a,(b_lo)
        call phex
        ld a,(pass)
        and 1
        ld de,m_on
        jr z,rep1
        ld de,m_off
rep1:   call puts
        ld de,m_rd
        call puts
        ld hl,(e_rd)
        call pdec
        ld de,m_vf
        call puts
        ld hl,(e_vf)
        call pdec
        ld de,m_tot
        call puts
        ld hl,(tot_rd)
        call pdec
        ld de,m_slash
        call puts
        ld hl,(tot_vf)
        call pdec
        ld de,m_crlf
        call puts

        ld a,(nrec)             ; first errors
        or a
        jr z,rep6
        ld b,a
        ld hl,recs
rep4:   push bc
        ld de,m_sp
        call puts
        ld a,(hl)               ; kind
        inc hl
        call putc
        ld a,' '
        call putc
        ld a,(hl)
        inc hl
        call phex1
        ld a,(hl)
        inc hl
        call phex
        ld a,(hl)
        inc hl
        call phex
        ld de,m_exp
        call puts
        ld a,(hl)
        inc hl
        call phex
        ld de,m_got
        call puts
        ld a,(hl)
        inc hl
        call phex
        ld a,(hl)               ; distance (0: verify)
        inc hl
        or a
        jr z,rep5
        push hl
        ld de,m_dist
        call puts
        ld l,a
        ld h,0
        ld a,l
        cp 0FFh                 ; FFh: 256 or more
        jr nz,rep4b
        ld de,m_big
        call puts
        jr rep4c
rep4b:  call pdec
rep4c:  pop hl
rep5:   ld de,m_crlf
        call puts
        pop bc
        djnz rep4

rep6:   ld hl,(pass)
        inc hl
        ld (pass),hl
        ld c,0Bh                ; key pressed?
        call BDOS
        or a
        jp z,pass_l
        ld c,08h                ; take it
        call BDOS
        ld a,8                  ; display off: the main screen again
        out (P_RSEL),a
        xor a
        out (P_RDATA),a
        ld a,(turbor)
        or a
        jr z,end1
        ld a,(oldcpu)
        or 80h
        ld iy,(EXPTBL-1)
        ld ix,CHGCPU
        call CALSLT
end1:   ld de,m_end
        call puts
        ret

; ---- write pointer R#0-R#2 = base + HL (HL < 16 KB) -------------------
setw:   ld a,(b_lo)
        add a,l
        ld l,a
        ld a,(b_mid)
        adc a,h
        ld h,a
        ld a,(b_hi)
        adc a,0
        ld c,a
        xor a                   ; R#0, auto increment
        out (P_RSEL),a
        ld a,l
        out (P_RDATA),a
        ld a,h
        out (P_RDATA),a
        ld a,c
        out (P_RDATA),a
        ret

; ---- s_hi / s_mid / s_lo = base + (HL and 3FFFh) ----------------------
addr:   ld a,h
        and 3Fh
        ld c,a
        ld a,(b_lo)
        add a,l
        ld (s_lo),a
        ld a,(b_mid)
        adc a,c
        ld (s_mid),a
        ld a,(b_hi)
        adc a,0
        ld (s_hi),a
        ret

; ---- (DE) += HL, up to 65535 ------------------------------------------
addsat: ex de,hl
        ld c,(hl)
        inc hl
        ld b,(hl)
        ex de,hl
        add hl,bc
        jr nc,ads1
        ld hl,0FFFFh
ads1:   ex de,hl
        ld (hl),d
        dec hl
        ld (hl),e
        ret

; ---- an error of kind C ('R' / 'V'): s_*, expv, gotv, dist ------------
error:  push hl
        ld hl,e_rd
        ld a,c
        cp 'R'
        jr z,err0
        ld hl,e_vf
err0:   ld e,(hl)               ; count, up to 65535
        inc hl
        ld d,(hl)
        inc de
        ld a,d
        or e
        jr z,err1
        ld (hl),d
        dec hl
        ld (hl),e
err1:   ld a,(nrec)
        cp NREC
        jr nc,err3
        ld e,a
        inc a
        ld (nrec),a
        ld a,e
        add a,a
        add a,a
        add a,a
        sub e                   ; * 7
        ld e,a
        ld d,0
        ld hl,recs
        add hl,de
        ld (hl),c
        inc hl
        ld a,(s_hi)
        ld (hl),a
        inc hl
        ld a,(s_mid)
        ld (hl),a
        inc hl
        ld a,(s_lo)
        ld (hl),a
        inc hl
        ld a,(expv)
        ld (hl),a
        inc hl
        ld a,(gotv)
        ld (hl),a
        inc hl
        ld a,(dist+1)           ; distance, FFh if 256 or more
        or a
        ld a,(dist)
        jr z,err2
        ld a,0FFh
err2:   ld (hl),a
err3:   pop hl
        ret

; ---- 16 bit xorshift (J. Metcalf), A = random byte --------------------
rnd:    push hl
        ld hl,(seed)
        ld a,h
        rra
        ld a,l
        rra
        xor h
        ld h,a
        ld a,l
        rra
        ld a,h
        rra
        xor l
        ld l,a
        xor h
        ld h,a
        ld (seed),hl
        pop hl
        ret

; ---- output -----------------------------------------------------------
pdec:   push bc                 ; HL in decimal
        push de
        push hl
        ld b,0                  ; 1 once a digit is printed
        ld de,-10000
        call pdec1
        ld de,-1000
        call pdec1
        ld de,-100
        call pdec1
        ld de,-10
        call pdec1
        ld a,l
        add a,'0'
        call putc
        pop hl
        pop de
        pop bc
        ret
pdec1:  ld a,'0'-1
pdec2:  inc a
        add hl,de
        jr c,pdec2
        sbc hl,de               ; carry 0: back
        cp '0'
        jr nz,pdec3
        bit 0,b
        ret z
pdec3:  ld b,1
        jp putc

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
; register, value; FFh ends
initregs:
        db 8,02h                ; display off, VRAM 512 KB
        db 9,00h                ; no interrupts
        db 6,05h                ; P1, as GNG (logical = physical address)
        db 7,00h                ; NTSC, not interlaced
        db 13,40h               ; 8 bpp: 256 colors (GRB 332)
        db 15,00h               ; backdrop
        db 16,00h               ; display adjust
        db 17,00h,18,00h,19,00h,20,00h  ; scroll A
        db 21,00h,22,00h,23,00h,24,00h  ; scroll B
        db 0FFh

; copy distances: mostly short, as the GNG data
dtab:   dw 1,1,1,1,2,2,3,4,5,7,8,16,33,256,513,1024

m_title: db "V9990 VRAM read-back test, P1 (GNG decompressor). Any key stops.",13,10,'$'
m_pass:  db "Pass $"
m_at:    db " at $"
m_on:    db " on : $"
m_off:   db " off: $"
m_rd:    db "read-back $"
m_vf:    db " verify $"
m_tot:   db "  total $"
m_slash: db "/$"
m_sp:    db "  $"
m_exp:   db " exp $"
m_got:   db " got $"
m_dist:  db " d=$"
m_big:   db ">255$"
m_end:   db "Stopped.",13,10,'$'
m_crlf:  db 13,10,'$'

seed:    dw 1
turbor:  db 0
oldcpu:  db 0
tot_rd:  dw 0
tot_vf:  dw 0
pass:    dw 0
end_vars:
e_rd:    dw 0
e_vf:    dw 0
nrec:    db 0
b_lo:    db 0
b_mid:   db 0
b_hi:    db 0
s_lo:    db 0
s_mid:   db 0
s_hi:    db 0
expv:    db 0
gotv:    db 0
dist:    dw 0
recs:    ds NREC*RECSZ
