; SCCCMP.COM: compares a ROM loaded in the MegaSCC+ of slot 1 with its file, MSX-DOS 2 / Nextor.
; Assemble: pasmo SCCCMP.ASM SCCCMP.COM
;
; Usage: ROMLOAD file.ROM   (without /S or /R: it loads and returns to DOS)
;        SCCCMP file.ROM
; For each 8 KB bank of the file: B000h = bank, the bank read at A000h-BFFFh
; of slot 1 (page 2) and compared with the file.  Prints the bank numbers
; that differ, with the first different offset, the file byte and the
; cartridge byte.  The banks go through B000h only (A000h-BFFFh has no SCC
; registers in SCC mode, as 9800h-9FFFh has).

BDOS    equ 5
ENASLT  equ 0024h
RAMAD2  equ 0F343h              ; slot of the RAM in page 2
BUF     equ 4000h               ; 8 KB in page 1
SLOT    equ 01h                 ; primary slot 1, not expanded

        org 100h

start:  ld de,m_title
        call puts
        ld hl,81h               ; file name from the command line
skp:    ld a,(hl)
        cp ' '
        jr nz,nm1
        inc hl
        jr skp
nm1:    or a
        jp z,usage
        cp 13
        jp z,usage
        ld de,fname
nm2:    ld a,(hl)
        or a
        jr z,nm3
        cp 13
        jr z,nm3
        cp ' '
        jr z,nm3
        ld (de),a
        inc hl
        inc de
        jr nm2
nm3:    xor a
        ld (de),a
        ld de,fname             ; open
        xor a
        ld c,43h
        call BDOS
        or a
        jp nz,ferr
        ld a,b
        ld (handle),a
        xor a
        ld (bank),a
        ld (nbad),a

bank_l: ld a,(handle)           ; next 8 KB of the file
        ld b,a
        ld de,BUF
        ld hl,2000h
        ld c,48h
        call BDOS
        ld a,h                  ; end of file: less than 8 KB
        cp 20h
        jp nz,done

        di
        ld a,SLOT               ; cartridge in page 2
        ld h,80h
        call ENASLT
        di
        ld a,(bank)
        ld (0B000h),a
        ld hl,0A000h
        ld de,BUF
        ld bc,2000h
cmp1:   ld a,(de)
        cp (hl)
        jr nz,cmp2
        inc hl
        inc de
        dec bc
        ld a,b
        or c
        jr nz,cmp1
        jr cmp3
cmp2:   ld (boff),hl            ; first difference
        ld (bfile),a
        ld a,(hl)
        ld (bcart),a
        ld a,1
        ld (isbad),a
cmp3:   ld a,(RAMAD2)           ; RAM back in page 2
        ld h,80h
        call ENASLT
        ei

        ld a,(isbad)
        or a
        jr z,next
        xor a
        ld (isbad),a
        ld hl,nbad
        inc (hl)
        ld de,m_bank
        call puts
        ld a,(bank)
        call phex
        ld de,m_at
        call puts
        ld hl,(boff)
        ld a,h
        call phex
        ld a,l
        call phex
        ld de,m_file
        call puts
        ld a,(bfile)
        call phex
        ld de,m_cart
        call puts
        ld a,(bcart)
        call phex
        ld de,m_crlf
        call puts

next:   ld a,(bank)
        inc a
        ld (bank),a
        jp nz,bank_l

done:   ld a,(handle)
        ld b,a
        ld c,45h
        call BDOS
        ld de,m_banks
        call puts
        ld a,(bank)
        call phex
        ld de,m_bad
        call puts
        ld a,(nbad)
        call phex
        ld de,m_crlf
        jp puts

usage:  ld de,m_usage
        jp puts
ferr:   ld de,m_ferr
        jp puts

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

handle: db 0
bank:   db 0
nbad:   db 0
isbad:  db 0
bfile:  db 0
bcart:  db 0
boff:   dw 0
m_title: db "MegaSCC+ (slot 1) contents vs ROM file",13,10,'$'
m_usage: db "Usage: SCCCMP file.ROM (after ROMLOAD file.ROM without /S)",13,10,'$'
m_ferr:  db "File error.",13,10,'$'
m_bank:  db "bank $"
m_at:    db " differs at $"
m_file:  db " file $"
m_cart:  db " cart $"
m_banks: db "Banks compared (hex) $"
m_bad:   db ", bad $"
m_crlf:  db 13,10,'$'
fname:  ds 64
