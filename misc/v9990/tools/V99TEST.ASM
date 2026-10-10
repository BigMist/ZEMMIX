; V99TEST.COM: V9990 (GFX9000) VRAM test for ZEMMIX, MSX-DOS 2 / Nextor.
; Assemble: pasmo V99TEST.ASM V99TEST.COM
;
; Writes the whole 512 KB VRAM through P#0 and reads it back, pass after
; pass, until a key is pressed.  The screen is mode B1 (256 x 212, 8 bpp),
; so the test pattern is visible.  Even passes run with the display on (the
; V9990 reads the VRAM to draw while the CPU tests it), odd passes with the
; display off; every second pair of passes the pattern is inverted.
;
; After each pass: its errors, the totals with display on / off, the first
; errors of the pass (logical address, written, read) and, if there were
; errors, how many times each data bit failed in the even bytes (low half of
; the SDRAM word, DQ0-7) and in the odd bytes (high half, DQ8-15).

BDOS    equ 5
P_VRAM  equ 60h                 ; P#0 VRAM data
P_RDATA equ 63h                 ; P#3 register data
P_RSEL  equ 64h                 ; P#4 register select (bits 7/6 = 0: auto increment)
P_SYS   equ 67h                 ; P#7 system control
NREC    equ 6                   ; errors listed per pass

        org 100h

start:  ld de,m_title
        call puts
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
init2:  ld hl,bitcnt            ; clear the counters
        ld b,end_vars-bitcnt
        xor a
clr1:   ld (hl),a
        inc hl
        djnz clr1

; ---- one pass ---------------------------------------------------------
pass_l: ld hl,0
        ld (perr),hl
        xor a
        ld (nrec),a
        ld a,(pass)
        ld b,a
        add a,a                 ; base = pass * 43
        add a,a
        add a,b
        add a,a
        add a,a
        add a,b
        add a,a
        add a,b                 ; any odd step is fine
        ld (base),a
        ld a,b
        and 2
        jr z,pass1
        ld a,0FFh
pass1:  ld (inv),a
        ld a,b
        and 1
        ld a,82h                ; R#8: display on, VRAM 512 KB
        jr z,pass2
        ld a,02h                ; display off
pass2:  ld c,a
        ld a,8
        out (P_RSEL),a
        ld a,c
        out (P_RDATA),a

        ; write: R#0-R#2 = 0, increment on
        xor a
        out (P_RSEL),a
        out (P_RDATA),a
        out (P_RDATA),a
        out (P_RDATA),a
        ld hl,0
        ld (blk),hl
wr_l:   call mkbuf
        ld hl,buf
        ld bc,P_VRAM            ; B = 0: 256 bytes
        otir
        ld hl,(blk)
        inc hl
        ld (blk),hl
        ld a,h
        cp 8                    ; 2048 blocks of 256 bytes
        jr nz,wr_l

        ; read: R#3-R#5 = 0 (R#5 starts the read)
        ld a,3
        out (P_RSEL),a
        xor a
        out (P_RDATA),a
        out (P_RDATA),a
        out (P_RDATA),a
        ld hl,0
        ld (blk),hl
rd_l:   call mkbuf
        ld hl,buf
        ld b,0
rd_i:   in a,(P_VRAM)
        xor (hl)
        call nz,error
        inc hl
        djnz rd_i
        ld hl,(blk)
        inc hl
        ld (blk),hl
        ld a,h
        cp 8
        jr nz,rd_l

; ---- report -----------------------------------------------------------
        ld hl,(perr)            ; totals
        ld a,(pass)
        and 1
        ld de,tot_on
        jr z,rep1
        ld de,tot_off
rep1:   ex de,hl
        ld c,(hl)
        inc hl
        ld b,(hl)
        ex de,hl                ; HL = errors of the pass, BC = total, DE -> total + 1
        add hl,bc
        jr nc,rep2
        ld hl,0FFFFh
rep2:   ex de,hl
        ld (hl),d
        dec hl
        ld (hl),e

        ld de,m_pass
        call puts
        ld hl,(pass)
        call pdec
        ld a,(pass)
        and 1
        ld de,m_on
        jr z,rep3
        ld de,m_off
rep3:   call puts
        ld hl,(perr)
        call pdec
        ld de,m_tot
        call puts
        ld hl,(tot_on)
        call pdec
        ld de,m_slash
        call puts
        ld hl,(tot_off)
        call pdec
        ld de,m_crlf
        call puts

        ld a,(nrec)             ; first errors
        or a
        jr z,rep6
        ld b,a
        ld hl,recs
rep4:   push bc
        ld de,m_addr
        call puts
        ld a,(hl)               ; blk high: address bits 18-16
        inc hl
        call phex1
        ld a,(hl)               ; blk low: bits 15-8
        inc hl
        call phex
        ld a,(hl)               ; byte: bits 7-0
        inc hl
        call phex
        ld de,m_wrote
        call puts
        ld a,(hl)
        inc hl
        call phex
        ld de,m_read
        call puts
        ld a,(hl)
        inc hl
        call phex
        ld de,m_crlf
        call puts
        pop bc
        djnz rep4

        ld de,m_even            ; bits, totals of all passes
        call puts
        ld hl,bitcnt
        call pbits
        ld de,m_odd
        call puts
        ld hl,bitcnt+16
        call pbits

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
        ld de,m_end
        call puts
        ret

; ---- the pattern of a block of 256 bytes ------------------------------
; buf[i] = (i + blk.lo * 7 + blk.hi * 13 + base) xor inv
mkbuf:  ld a,(blk)
        ld c,a
        add a,a
        add a,a
        add a,a
        sub c                   ; * 7
        ld c,a
        ld a,(blk+1)
        ld b,a
        add a,a
        add a,b
        add a,a
        add a,a
        add a,b                 ; * 13
        add a,c
        ld c,a
        ld a,(base)
        add a,c
        ld c,a
        ld a,(inv)
        ld d,a
        ld hl,buf
        ld b,0
mkb1:   ld a,c
        xor d
        ld (hl),a
        inc hl
        inc c
        djnz mkb1
        ret

; ---- an error: A = bits that differ, HL -> expected byte (L = byte) ---
error:  ld (ediff),a
        ld (eptr),hl
        push hl
        push bc
        push de
        ld hl,(perr)            ; errors of the pass, up to 65535
        inc hl
        ld a,h
        or l
        jr nz,err1
        dec hl
err1:   ld (perr),hl

        ld a,(nrec)             ; record: blk hi, blk lo, byte, written, read
        cp NREC
        jr nc,err2
        ld e,a
        inc a
        ld (nrec),a
        ld a,e
        add a,a
        add a,a
        add a,e                 ; * 5
        ld e,a
        ld d,0
        ld hl,recs
        add hl,de
        ld a,(blk+1)
        ld (hl),a
        inc hl
        ld a,(blk)
        ld (hl),a
        inc hl
        ld de,(eptr)
        ld a,e
        ld (hl),a
        inc hl
        ld a,(de)
        ld (hl),a
        inc hl
        ld e,a
        ld a,(ediff)
        xor e
        ld (hl),a

err2:   ld a,(eptr)             ; bit counters: even bytes then odd bytes
        and 1
        add a,a
        add a,a
        add a,a
        add a,a                 ; 16 bytes each
        ld e,a
        ld d,0
        ld hl,bitcnt
        add hl,de
        ld a,(ediff)
        ld b,8
err3:   rrca
        jr nc,err5
        inc (hl)                ; word + 1, up to 65535
        jr nz,err5
        inc hl
        inc (hl)
        dec hl
        jr nz,err5
        ld (hl),0FFh
        inc hl
        ld (hl),0FFh
        dec hl
err5:   inc hl
        inc hl
        djnz err3
        pop de
        pop bc
        pop hl
        ret

; ---- output -----------------------------------------------------------
pbits:  ld b,8                  ; HL -> 8 words
pbt1:   push bc
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        push hl
        ex de,hl
        ld a,' '
        call putc
        call pdec
        pop hl
        pop bc
        djnz pbt1
        ld de,m_crlf
        jp puts

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
        db 6,82h                ; bitmap, 256 wide, 8 bpp (B1 with MCS 0)
        db 7,00h                ; NTSC, not interlaced
        db 13,40h               ; 8 bpp: 256 colors (GRB 332)
        db 15,00h               ; backdrop
        db 16,00h               ; display adjust
        db 17,00h,18,00h,19,00h,20,00h  ; scroll A
        db 21,00h,22,00h,23,00h,24,00h  ; scroll B
        db 0FFh

m_title: db "V9990 VRAM test (512 KB, mode B1). Any key stops.",13,10,'$'
m_pass:  db "Pass $"
m_on:    db " display on : errors $"
m_off:   db " display off: errors $"
m_tot:   db "  total on/off $"
m_slash: db "/$"
m_addr:  db "  bad $"
m_wrote: db " wrote $"
m_read:  db " read $"
m_even:  db "  even D0-7 :$"
m_odd:   db "  odd  D8-15:$"
m_end:   db "Stopped.",13,10,'$'
m_crlf:  db 13,10,'$'

bitcnt:  ds 32                  ; 2 x 8 words: errors of each bit
tot_on:  dw 0
tot_off: dw 0
pass:    dw 0
end_vars:
perr:    dw 0
nrec:    db 0
base:    db 0
inv:     db 0
blk:     dw 0
ediff:   db 0
eptr:    dw 0
recs:    ds NREC*5

        ds 256-($ and 255)      ; buf aligned: L = byte of the block
buf:     ds 256
