; OTIR / INIR test: OTIR 5 bytes to port 10h (logged by the harness as port 1? no: port 10h)
        org 100h
        ld sp,0E000h
        ld hl,msg
        ld b,5
        ld c,01h          ; console port of the harness
        otir
        ld a,b
        add a,'0'
        ld e,a
        ld c,2
        call 5            ; prints B (0)
        jp 0
msg:    db "OTIR!"
