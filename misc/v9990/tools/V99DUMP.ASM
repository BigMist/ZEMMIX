; V99DUMP.COM: V9990 (GFX9000) VRAM dump for ZEMMIX, MSX-DOS 2 / Nextor.
; Assemble: pasmo V99DUMP.ASM V99DUMP.COM
;
; Saves the 512 KB VRAM of the V9990 to V99VRAM.BIN in the current
; directory, in P1 order (logical address = physical address, as the
; openMSX "physical VRAM" debuggable).  The VRAM keeps its contents over
; an MSX reset, so a game screen can be dumped: run the game up to the
; screen, take the game cartridge out of the slot in the OSD, reset, and
; run V99DUMP.  It only sets R#6 (P1) and reads through P#0: the display
; and the other registers are left alone.

BDOS    equ 5
P_VRAM  equ 60h                 ; P#0 VRAM data
P_RDATA equ 63h                 ; P#3 register data
P_RSEL  equ 64h                 ; P#4 register select
BUF     equ 8000h               ; 16 KB

        org 100h

start:  ld de,m_title
        call puts
        ld de,fname             ; create the file
        xor a
        ld b,0
        ld c,44h
        call BDOS
        or a
        jr nz,fail
        ld a,b
        ld (handle),a

        ld a,6                  ; R#6 = 05h: P1, physical = logical
        out (P_RSEL),a
        ld a,05h
        out (P_RDATA),a
        ld a,3                  ; R#3-R#5 = 0: read from 00000h
        out (P_RSEL),a
        xor a
        out (P_RDATA),a
        out (P_RDATA),a
        out (P_RDATA),a

        ld a,32                 ; 32 blocks of 16 KB
        ld (blocks),a
blk1:   ld hl,BUF
        ld d,64                 ; 64 x 256 bytes
blk2:   ld bc,P_VRAM            ; B = 0: 256 bytes
        inir
        dec d
        jr nz,blk2
        ld a,(handle)
        ld b,a
        ld de,BUF
        ld hl,4000h
        ld c,49h                ; write
        call BDOS
        or a
        jr nz,fail
        ld a,'.'
        call putc
        ld a,(blocks)
        dec a
        ld (blocks),a
        jr nz,blk1

        ld a,(handle)
        ld b,a
        ld c,45h                ; close
        call BDOS
        ld de,m_ok
        jp puts

fail:   ld de,m_fail
        jp puts

putc:   ld e,a
        ld c,02h
        jp BDOS

puts:   ld c,09h
        jp BDOS

fname:  db "V99VRAM.BIN",0
handle: db 0
blocks: db 0
m_title: db "V9990 VRAM dump to V99VRAM.BIN (512 KB)",13,10,'$'
m_ok:    db 13,10,"Done.",13,10,'$'
m_fail:  db 13,10,"Disk error.",13,10,'$'
