; V99PLAY.COM: replays a V9990 (GFX9000) I/O trace for ZEMMIX, MSX-DOS 2 / Nextor.
; Assemble: pasmo V99PLAY.ASM V99PLAY.COM
;
; Usage: V99PLAY   (reads V99GNG.DAT in the current directory)
; The file is the port writes of a program captured in openMSX, made by a
; script on the PC:
;   00h-0Fh v       OUT (60h + n),v
;   10h             wait for CE = 0 (P#5 bit 0): before each command and
;                   where the program polled P#5
;   11h nl nh data  nh * 256 + nl bytes to P#0
;   FFh             end
; Reads are not replayed (the VRAM, registers and palette only depend on
; the writes).  Then V99DUMP saves the VRAM to compare it with openMSX.

BDOS    equ 5
P_VRAM  equ 60h
P_STAT  equ 65h
BUF     equ 8000h
BUFSZ   equ 4000h

        org 100h

start:  ld de,m_title
        call puts
        ld de,fname
open:   xor a                   ; open, read
        ld c,43h
        call BDOS
        or a
        jp nz,fail
        ld a,b
        ld (handle),a
        ld de,0                 ; nothing in the buffer
        ld hl,BUF

loop:   call getb
        cp 10h
        jr c,wr1
        jr z,wce
        cp 11h
        jr z,blk
        cp 0FFh
        jr z,done
        jp bad

wr1:    add a,60h               ; OUT (60h + n),v
        ld c,a
        call getb
        out (c),a
        jr loop

wce:    in a,(P_STAT)
        rrca
        jr c,wce
        jr loop

blk:    call getb
        ld (cnt),a
        call getb
        ld (cnt+1),a
blk1:   call getb
        out (P_VRAM),a
        push hl
        ld hl,(cnt)
        dec hl
        ld (cnt),hl
        ld a,h
        or l
        pop hl
        jr nz,blk1
        jr loop

done:   ld a,(handle)
        ld b,a
        ld c,45h
        call BDOS
        ld de,m_ok
        jp puts

bad:    ld de,m_bad
        jp puts

; ---- next byte of the file in A (HL pointer, DE bytes left) -----------
getb:   ld a,d
        or e
        jr z,refill
getb1:  dec de
        ld a,(hl)
        inc hl
        ret
refill: push bc
        ld e,'.'                ; progress: a dot every 16 KB
        ld c,02h
        call BDOS
        ld a,(handle)
        ld b,a
        ld de,BUF
        ld hl,BUFSZ
        ld c,48h                ; read
        call BDOS
        ex de,hl                ; DE = bytes read
        ld hl,BUF
        pop bc
        ld a,d
        or e
        jr nz,getb1
        pop af                  ; end of file in the middle: stop
fail:   ld de,m_fail
        jp puts

puts:   ld c,09h
        jp BDOS

fname:  db "V99GNG.DAT",0
handle: db 0
cnt:    dw 0
m_title: db "V9990 I/O trace replay",13,10,'$'
m_ok:    db 13,10,"Done. Now V99DUMP.",13,10,'$'
m_bad:   db 13,10,"Bad trace byte.",13,10,'$'
m_fail:  db 13,10,"File error.",13,10,'$'
