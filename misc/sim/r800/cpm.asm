; mini CP/M for zexdoc / zexall on the R800 core simulation
; 0000: first time JP 0100h, then exit (OUT (02h)); 0005: JP BDOS at F000h
; (zexdoc takes its stack from (0006h)); BDOS 2 (char in E), 9 (string at DE)
        org 0
        jp boot
        nop
        nop
        org 5
        jp bdos
        org 10h
boot:   ld a,(started)
        or a
        jr nz,exit
        inc a
        ld (started),a
        ld sp,0F000h
        jp 0100h
exit:   out (02h),a
        halt
started: db 0
        org 0F000h
bdos:   ld a,c
        cp 2
        jr z,pchar
        cp 9
        ret nz
pstr:   ld a,(de)
        cp '$'
        ret z
        out (01h),a
        inc de
        jr pstr
pchar:  ld a,e
        out (01h),a
        ret
