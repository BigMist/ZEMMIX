; VDPDUMP.COM: saves the 128 KB of VDP VRAM to VRAM.BIN (MSX-DOS 2 / Nextor).
; Assemble: pasmo VDPDUMP.ASM VDPDUMP.COM
;
; Reads the VRAM through 98h in 8 blocks of 16 KB (R#14 = block) and writes
; them to VRAM.BIN in the current directory.  For ZEMMIX debugging: run a
; program, reset (the VRAM of the V9968 is block RAM and is kept),
; boot and dump; the BIOS rewrites only the start of the VRAM.

BDOS    equ 5
P_DATA  equ 98h
P_CTRL  equ 99h
_CREATE equ 44h
_WRITE  equ 49h
_CLOSE  equ 45h
BUF     equ 4000h                ; 16 KB buffer at 4000h-7FFFh (TPA)

        org 100h

start:  ld de,m_title
        ld c,09h
        call BDOS
        ld de,fname
        xor a                   ; open mode
        ld b,0                  ; attributes
        ld c,_CREATE
        call BDOS
        or a
        jr nz,err
        ld a,b
        ld (fh),a
        xor a
        ld (blk),a
loop:   di
        ld a,(blk)
        out (P_CTRL),a
        ld a,14 or 80h          ; R#14 = block
        out (P_CTRL),a
        xor a
        out (P_CTRL),a          ; read address 0000h
        out (P_CTRL),a
        ld hl,BUF
        ld bc,0                 ; 64 x 256 = 16384
        ld d,64
rd:     ld b,0
        push de
        ld c,P_DATA
        inir
        pop de
        dec d
        jr nz,rd
        ei
        ld a,(fh)
        ld b,a
        ld de,BUF
        ld hl,4000h
        ld c,_WRITE
        call BDOS
        or a
        jr nz,err
        ld e,'.'
        ld c,02h
        call BDOS
        ld a,(blk)
        inc a
        ld (blk),a
        cp 8
        jr nz,loop
        ld a,(fh)
        ld b,a
        ld c,_CLOSE
        call BDOS
        ld de,m_ok
        ld c,09h
        jp BDOS
err:    ld de,m_err
        ld c,09h
        jp BDOS

fname:  db "VRAM.BIN",0
fh:     db 0
blk:    db 0
m_title: db "VDPDUMP: VRAM 128 KB to VRAM.BIN ",'$'
m_ok:   db " OK",13,10,'$'
m_err:  db " error",13,10,'$'
