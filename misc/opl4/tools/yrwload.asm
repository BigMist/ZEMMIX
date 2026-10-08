; YRWLOAD.COM - loads YRW801.ROM (2 MB) into the OPL4 wave memory of the ZEMMIX
; through the memory registers on ports 7Eh/7Fh (opl4_memtest, ZEMMIX-0au.4),
; then reads it back and compares it with the file. MSX-DOS 2 / Nextor.
; YRWLOAD V only compares (the firmware loads ZEMMIX.ROM when the core starts).
; With the real OPL4 the ROM area is read only: YRWLOAD V is the useful mode.

BDOS    equ     5
_STROUT equ     09h
_OPEN   equ     43h
_CLOSE  equ     45h
_READ   equ     48h
_TERM   equ     62h

OPLIDX  equ     7Eh
OPLDAT  equ     7Fh

BUF1    equ     4000h           ; wave memory read back
BUF2    equ     8000h           ; file data
CHUNK   equ     4000h           ; 16 KB, 128 chunks = 2 MB

        org     100h

        ld      de,msg_hello
        call    print

        ; NEW2 first: the wave registers of the OPL4 answer only with it
        ld      a,5
        out     (0C6h),a
        ld      a,3
        out     (0C7h),a
        ; ID check
        ld      a,2
        out     (OPLIDX),a
        in      a,(OPLDAT)
        and     0E0h                    ; device ID in bits 7-5
        cp      20h
        jr      z,id_ok
        ld      de,msg_noid
        call    print
        jp      exit
id_ok:
        ld      a,2                     ; memory access mode on (reg 02h bit 0)
        out     (OPLIDX),a
        ld      a,1
        out     (OPLDAT),a

        ; YRWLOAD V: verify only
        ld      hl,80h
        ld      b,(hl)
        inc     b
args:
        dec     b
        jr      z,do_load
        inc     hl
        ld      a,(hl)
        and     0DFh                    ; upper case
        cp      'V'
        jr      nz,args
        jp      verify
do_load:
        ; ---------------------------------------------------------------- load
        call    open
        call    set_adr0
        ld      a,6
        out     (OPLIDX),a
        ld      de,msg_load
        call    print
        ld      a,128
        ld      (count),a
load_loop:
        call    read_chunk
        ld      hl,BUF2
        ld      c,OPLDAT
        ld      d,CHUNK/256
load_out:
        ld      b,0
        otir
        dec     d
        jr      nz,load_out
        call    dot
        ld      hl,count
        dec     (hl)
        jr      nz,load_loop
        call    close

        ; -------------------------------------------------------------- verify
verify:
        call    open
        call    set_adr0                ; starts the read of byte 0
        ld      a,6
        out     (OPLIDX),a
        ld      de,msg_verify
        call    print
        ld      hl,0
        ld      (errors),hl
        ld      a,128
        ld      (count),a
ver_loop:
        call    read_chunk
        ld      hl,BUF1
        ld      c,OPLDAT
        ld      d,CHUNK/256
ver_in:
        ld      b,0
        inir
        dec     d
        jr      nz,ver_in
        ld      hl,BUF1
        ld      de,BUF2
        ld      bc,CHUNK
ver_cmp:
        ld      a,(de)
        cp      (hl)
        jr      z,ver_same
        push    hl
        ld      hl,(errors)
        inc     hl
        ld      a,h
        or      l
        jr      nz,ver_cnt
        dec     hl                      ; stays at FFFFh
ver_cnt:
        ld      (errors),hl
        pop     hl
ver_same:
        inc     hl
        inc     de
        dec     bc
        ld      a,b
        or      c
        jr      nz,ver_cmp
        call    dot
        ld      hl,count
        dec     (hl)
        jr      nz,ver_loop
        call    close

        ld      de,msg_errors
        call    print
        ld      a,(errors+1)
        call    hex8
        ld      a,(errors)
        call    hex8
        ld      de,msg_crlf
        call    print
exit:
        ld      a,2                     ; memory access mode off
        out     (OPLIDX),a
        xor     a
        out     (OPLDAT),a
        ld      b,0
        ld      c,_TERM
        jp      BDOS

; ------------------------------------------------------------------ helpers
set_adr0:
        ld      a,3
        out     (OPLIDX),a
        xor     a
        out     (OPLDAT),a
        ld      a,4
        out     (OPLIDX),a
        xor     a
        out     (OPLDAT),a
        ld      a,5
        out     (OPLIDX),a
        xor     a
        out     (OPLDAT),a
        ret

open:
        ld      de,fname
        ld      a,1                     ; no write
        ld      c,_OPEN
        call    BDOS
        or      a
        jr      nz,err_file
        ld      a,b
        ld      (handle),a
        ret

close:
        ld      a,(handle)
        ld      b,a
        ld      c,_CLOSE
        jp      BDOS

read_chunk:
        ld      a,(handle)
        ld      b,a
        ld      de,BUF2
        ld      hl,CHUNK
        ld      c,_READ
        call    BDOS
        or      a
        jr      nz,err_file
        ld      a,h                     ; a full chunk or the file is too short
        cp      CHUNK/256
        jr      nz,err_file
        ret

err_file:
        ld      de,msg_file
        call    print
        jp      exit

dot:
        ld      de,msg_dot
print:
        ld      c,_STROUT
        jp      BDOS

hex8:
        push    af
        rrca
        rrca
        rrca
        rrca
        call    hex4
        pop     af
hex4:
        and     0Fh
        add     a,90h
        daa
        adc     a,40h
        daa
        ld      (msg_hex),a
        ld      de,msg_hex
        jr      print

fname:      db  "YRW801.ROM",0
msg_hello:  db  "YRWLOAD: YRW801 to the OPL4 wave memory (7Eh/7Fh)",13,10,"$"
msg_noid:   db  "No OPL4 memory test on 7Eh/7Fh (ID is not 20h)",13,10,"$"
msg_load:   db  "Loading",13,10,"$"
msg_verify: db  13,10,"Verifying",13,10,"$"
msg_errors: db  13,10,"Errors (bytes, hex): $"
msg_file:   db  13,10,"Cannot read YRW801.ROM (2 MB)",13,10,"$"
msg_dot:    db  ".$"
msg_crlf:   db  13,10,"$"
msg_hex:    db  "0$"
handle:     db  0
count:      db  0
errors:     dw  0
