; SNDOFF.COM: silences the sound chips of ZEMMIX one by one, MSX-DOS.
; Assemble: pasmo SNDOFF.ASM SNDOFF.COM
;
; To find which chip keeps a note after a reset: each step silences one
; chip and waits for a key, so the step where the sound stops names it.
;   1 PSG       (A0h/A1h)  volumes R#8-R#10 = 0, tone and noise off
;   2 OPLL      (7Ch/7Dh)  key off and volume 15 on the 9 channels, rhythm off
;   3 OPL3      (C4h-C7h)  key off on the 18 channels (both banks), release
;                          rate F, total level 3F on the 36 operators
;   4 OPL4 wave (7Eh/7Fh)  key off and damp on the 24 channels
;   5 PCM turbo R (A4h)    stop
; The MoonSound (OPL3 / OPL4 wave) needs its ports on (OSD MoonSound On).

BDOS    equ 5

        org 100h

start:  ld de,m_title
        call puts

        ld de,m_psg             ; 1 PSG
        call puts
        ld a,7                  ; tone and noise off, keep port I/O bits
        out (0A0h),a
        in a,(0A2h)
        or 3Fh
        out (0A1h),a
        ld b,3
        ld c,8
psg1:   ld a,c
        out (0A0h),a
        xor a
        out (0A1h),a
        inc c
        djnz psg1
        call wkey

        ld de,m_opll            ; 2 OPLL
        call puts
        ld a,0Eh                ; rhythm off
        ld e,0
        call opll
        ld c,20h                ; key off
        ld b,9
ol1:    ld a,c
        ld e,0
        call opll
        inc c
        djnz ol1
        ld c,30h                ; volume 15 (silent)
        ld b,9
ol2:    ld a,c
        ld e,0Fh
        call opll
        inc c
        djnz ol2
        call wkey

        ld de,m_opl3            ; 3 OPL3
        call puts
        ld hl,0C4C5h            ; bank 0: C4h / C5h
        call opl3b
        ld hl,0C6C7h            ; bank 1: C6h / C7h
        call opl3b
        call wkey

        ld de,m_opl4            ; 4 OPL4 wave
        call puts
        ld a,05h                ; OPL3 105h = 03h: NEW2, the wave ports on
        ld e,03h
        ld hl,0C6C7h
        call opl3
        ld c,68h                ; 68h-7Fh: key off, damp
        ld b,24
o4:     ld a,c
        out (7Eh),a
        call o4w
        ld a,40h
        out (7Fh),a
        call o4w
        inc c
        djnz o4
        call wkey

        ld de,m_pcm             ; 5 PCM
        call puts
        xor a
        out (0A4h),a
        out (0A5h),a
        call wkey

        ld de,m_end
        jp puts

; ---- OPLL register A = E -------------------------------------------------
opll:   out (7Ch),a
        push bc
        ld b,8
op1:    djnz op1
        ld a,e
        out (7Dh),a
        ld b,32
op2:    djnz op2
        pop bc
        ret

; ---- OPL3 bank: H = address port, L = data port ---------------------------
opl3b:  ld c,0B0h               ; key off: B0h-B8h = 0
        ld b,9
ob1:    ld a,c
        ld e,0
        call opl3
        inc c
        djnz ob1
        ld c,80h                ; sustain level / release rate F: 80h-95h
        ld b,16h
ob2:    ld a,c
        ld e,0FFh
        call opl3
        inc c
        djnz ob2
        ld c,40h                ; total level 3F: 40h-55h
        ld b,16h
ob3:    ld a,c
        ld e,3Fh
        call opl3
        inc c
        djnz ob3
        ret
opl3:   push bc                 ; register A = E, ports H / L
        ld c,h
        out (c),a
        ld b,4
o3a:    djnz o3a
        ld c,l
        out (c),e
        ld b,8
o3b:    djnz o3b
        pop bc
        ret

; ---- OPL4 wave: wait while BUSY (status C4h bit 0) -----------------------
o4w:    push bc                 ; (at most 256 tries: no MoonSound reads FFh)
        ld b,0
o4w1:   in a,(0C4h)
        rrca
        jr nc,o4w2
        djnz o4w1
o4w2:   pop bc
        ret

; ---- wait for a key ---------------------------------------------------------
wkey:   ld de,m_key
        call puts
        ld c,08h                ; console input, no echo
        call BDOS
        ld de,m_crlf
        jp puts

puts:   ld c,09h
        jp BDOS

m_title: db "SNDOFF: silence the sound chips one by one.",13,10
         db "Note the step where the stuck sound stops.",13,10,'$'
m_psg:   db "1 PSG off.$"
m_opll:  db "2 OPLL (MSX-MUSIC) off.$"
m_opl3:  db "3 OPL3 (MoonSound FM) off.$"
m_opl4:  db "4 OPL4 wave (MoonSound PCM) off.$"
m_pcm:   db "5 PCM (turbo R) off.$"
m_key:   db " Silent? Press a key.$"
m_end:   db "All off.",13,10,'$'
m_crlf:  db 13,10,'$'
