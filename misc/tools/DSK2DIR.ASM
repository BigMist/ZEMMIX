; DSK2DIR.COM: extracts the disk image inside a ROM (DSK2ROM and similar) to a
; directory, MSX-DOS 2 / Nextor.
; Assemble: pasmo DSK2DIR.ASM DSK2DIR.COM
;
; Usage: DSK2DIR file.ROM [directory]
;   without a directory, one with the name of the ROM file (LOEESP.ROM ->
;   LOEESP) is created in the current directory
;
; A disk converted to a MegaROM (DSK2ROM by joyrex and similar tools) keeps
; the FAT12 image of the disk after its driver.  DSK2DIR writes every file
; of the root directory and of its subdirectories into the directory given
; or named after the ROM (created if needed).  The game can then run from
; that directory, without the cartridge mapper or the disk driver of the
; ROM.
;
; Two kinds of image:
;   plain       the boot sector is looked for in the first 256 KB of the
;               file (bytes per sector 512, media F0h-FFh, 1 or 2 FATs)
;   compressed  DSK2ROM 0.80 with compression ("DSK2ROM" at 3FE0h, 02h at
;               3F00h, the 7F00h of its driver): a table at 4000h (8 KB bank
;               2) with 5 bytes per sector: 8 KB bank, address in 4000h-
;               5FFFh, length; the bytes go on in the next bank; length
;               200h is a stored sector, else BitBuster packed (the depacker
;               of the driver, 76B8h)

BDOS    equ 5
FATBUF  equ 8000h               ; the FAT, up to 16 KB
SECBUF  equ 4000h               ; a sector
CBUF    equ 4200h               ; a packed sector
MAXLVL  equ 8

        org 100h

start:  ld de,m_title
        call puts
        ld hl,81h               ; arguments: file and directory
        ld de,fname
        call arg
        ld a,(fname)
        or a
        jp z,usage
        ld de,dname
        call arg
        ld a,(dname)            ; no directory: the name of the ROM file
        or a
        call z,romdir

        ld b,0                  ; current directory, to come back
        ld de,cwd+1
        ld c,59h                ; _GETCWD
        call BDOS
        ld a,5Ch                ; \
        ld (cwd),a

        ld de,fname             ; open the ROM file
        xor a
        ld c,43h                ; _OPEN
        call BDOS
        or a
        jp nz,ferr
        ld a,b
        ld (hrom),a
        ld hl,0FFFFh
        ld (cursec),hl          ; no sector read yet

        ; ---- compressed DSK2ROM? ----
        ld hl,3FE0h
        call seek16
        ld de,ent
        ld hl,8
        call fread
        ld hl,ent
        ld de,m_d2r
        ld b,7
cmp1:   ld a,(de)
        cp (hl)
        jr nz,plain
        inc hl
        inc de
        djnz cmp1
        ld hl,3F00h
        call seek16
        ld de,ent
        ld hl,1
        call fread
        ld a,(ent)
        cp 2
        jr nz,plain
        ld a,1
        ld (comp),a
        ld hl,0                 ; the boot sector
        call rdsec
        ld hl,SECBUF
        ld de,ent
        ld bc,32
        ldir
        call isboot
        jp nz,nodisk
        ld de,m_comp
        call puts
        jp found

        ; ---- plain: the boot sector, every 512 bytes of the first 256 KB ----
plain:  ld hl,0
        ld (pos),hl
        ld (pos+2),hl
scan:   call fseek
        ld de,ent
        ld hl,32
        call fread
        ld a,h
        or a
        jr nz,scan1
        ld a,l
        cp 32
        jp nz,nodisk            ; end of file
scan1:  call isboot
        jr z,fnd0
        ld hl,(pos+1)           ; next 512 bytes: pos += 200h
        inc hl
        inc hl
        ld (pos+1),hl
        ld a,h
        cp 4                    ; 256 KB
        jr c,scan
        jp nodisk
fnd0:   ld hl,(pos)             ; the image starts here
        ld (base),hl
        ld hl,(pos+2)
        ld (base+2),hl
        ld de,m_found
        call puts
        ld a,(base+2)
        call phex
        ld a,(base+1)
        call phex
        ld a,(base)
        call phex
        ld a,'h'
        call putc

found:  ld a,(ent+0Dh)
        ld (spc),a
        ld hl,(ent+0Eh)         ; reserved sectors: the FAT
        ld (fatsec),hl
        ld de,(ent+16h)         ; sectors per FAT
        ld (spf),de
        ld a,(ent+10h)
        ld b,a
fnd1:   add hl,de
        djnz fnd1
        ld (rootsec),hl         ; root directory
        ld de,(ent+11h)
        ld (rootent),de
        ld b,4                  ; root entries / 16 = sectors
fnd2:   srl d
        rr e
        djnz fnd2
        add hl,de
        ld (datasec),hl
        ld hl,(ent+13h)
        ld (totsec),hl
        ld de,m_sect
        call puts
        ld hl,(totsec)
        call pdec
        ld de,m_crlf
        call puts

        ld hl,(spf)             ; the FAT in memory (up to 32 sectors)
        ld a,h
        or a
        jp nz,toobig
        ld a,l
        cp 33
        jp nc,toobig
        ld de,FATBUF
        ld hl,(fatsec)
fat1:   push de
        push hl
        call rdsec
        pop hl
        pop de
        push hl
        ld hl,SECBUF
        ld bc,512
        ldir
        pop hl
        inc hl
        ld a,(spf)
        dec a
        ld (spf),a
        jr nz,fat1

        ; ---- destination directory ----
        ld de,dname
        call mkcd
        jp nz,derr

        ; ---- walk the directories ----
        xor a
        ld (lvl),a
        ld hl,0
        ld (dcl),hl             ; level 0: root
        ld (didx),hl

next:   call getent
        jp c,lvlend
        call curidx             ; index + 1
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc de
        ld (hl),d
        dec hl
        ld (hl),e
        ld a,(ent)
        or a
        jp z,lvlend             ; no more entries
        cp 0E5h
        jr z,next               ; deleted
        cp '.'
        jr z,next               ; . and ..
        ld a,(ent+0Bh)
        and 08h
        jr nz,next              ; volume label
        call mkname
        ld a,(lvl)              ; indent
        or a
        jr z,nx1
        ld b,a
nx0:    ld a,' '
        call putc
        call putc
        djnz nx0
nx1:    ld hl,name
        call putz
        ld a,(ent+0Bh)
        and 10h
        jr nz,subdir

        ld de,m_crlf            ; a file
        call puts
        call extract
        jp nz,werr
        jp next

subdir: ld a,5Ch                ; \
        call putc
        ld de,m_crlf
        call puts
        ld a,(lvl)
        cp MAXLVL-1
        jp nc,deep
        ld de,name
        call mkcd
        jp nz,derr
        ld a,(lvl)
        inc a
        ld (lvl),a
        call curcl              ; first cluster
        ld de,(ent+1Ah)
        ld (hl),e
        inc hl
        ld (hl),d
        call curidx
        xor a
        ld (hl),a
        inc hl
        ld (hl),a
        jp next

lvlend: ld a,(lvl)
        or a
        jr z,done
        dec a
        ld (lvl),a
        ld de,m_up
        ld c,5Ah                ; _CHDIR ..
        call BDOS
        jp next

done:   ld a,(hrom)
        ld b,a
        ld c,45h
        call BDOS
        ld de,cwd               ; back to the directory of the start
        ld c,5Ah
        call BDOS
        ld de,m_done
        jp puts

; ---- Z if ent is a FAT12 boot sector ------------------------------------
isboot: ld a,(ent+0Bh)          ; bytes per sector 512
        or a
        ret nz
        ld a,(ent+0Ch)
        cp 2
        ret nz
        ld a,(ent+15h)          ; media F0h-FFh
        cp 0F0h
        jr c,isb9
        ld a,(ent+10h)          ; 1 or 2 FATs
        dec a
        cp 2
        jr nc,isb9
        ld a,(ent+0Dh)          ; sectors per cluster 1-32
        or a
        jr z,isb9
        cp 33
        jr nc,isb9
        ld hl,(ent+11h)         ; root entries, a multiple of 16
        ld a,h
        or l
        jr z,isb9
        ld a,l
        and 0Fh
        ret
isb9:   or 1
        ret

; ---- create directory DE (if needed) and enter it; NZ on error -------
mkcd:   push de
        xor a
        ld b,10h                ; directory
        ld c,44h                ; _CREATE
        call BDOS               ; it may exist already
        pop de
        ld c,5Ah                ; _CHDIR
        call BDOS
        or a
        ret

; ---- extract the file of ent to name; NZ on error -------------------
extract:
        ld de,name
        xor a
        ld b,0
        ld c,44h                ; _CREATE
        call BDOS
        or a
        ret nz
        ld a,b
        ld (hout),a
        ld hl,(ent+1Ch)         ; size
        ld (fsize),hl
        ld hl,(ent+1Eh)
        ld (fsize+2),hl
        ld hl,(ent+1Ah)
        ld (cl),hl
ex1:    ld hl,(cl)              ; a valid cluster
        ld de,2
        or a
        sbc hl,de
        jp c,ex9
        ld hl,(cl)
        ld de,0FF0h
        or a
        sbc hl,de
        jp nc,ex9
        ld hl,(cl)
        call clsec
        ld (secn),hl
        ld a,(spc)
        ld (secl),a
ex2:    ld hl,(fsize)           ; size 0: done
        ld a,h
        or l
        ld hl,(fsize+2)
        or h
        or l
        jp z,ex9
        ld hl,(secn)
        call rdsec
        ld hl,512               ; count = min(size, 512)
        ld de,(fsize+2)
        ld a,d
        or e
        jr nz,ex3
        ld de,(fsize)
        or a
        sbc hl,de
        add hl,de
        jr c,ex3
        ex de,hl
ex3:    ld (count),hl
        ld a,(hout)
        ld b,a
        ld de,SECBUF
        ld c,49h                ; _WRITE
        call BDOS
        or a
        jr nz,ex8
        ld hl,(fsize)           ; size -= count
        ld de,(count)
        or a
        sbc hl,de
        ld (fsize),hl
        ld hl,(fsize+2)
        ld de,0
        sbc hl,de
        ld (fsize+2),hl
        ld hl,(secn)
        inc hl
        ld (secn),hl
        ld a,(secl)
        dec a
        ld (secl),a
        jr nz,ex2
        ld hl,(cl)
        call fatnext
        ld (cl),hl
        jp ex1
ex8:    push af
        call ex9
        pop af
        or a
        ret
ex9:    ld a,(hout)
        ld b,a
        ld c,45h                ; _CLOSE
        call BDOS
        xor a
        ret

; ---- entry didx of the current directory in ent; carry at the end ---
getent: call curidx
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (tidx),de
        call curcl
        ld a,(hl)
        inc hl
        or (hl)
        jr nz,ge_sub
        ld de,(rootent)         ; root: rootsec + idx / 16
        ld hl,(tidx)
        push hl
        or a
        sbc hl,de
        pop hl
        ccf
        ret c
        push hl
        ld hl,(rootsec)
        ld (secb),hl
        pop hl
        jr ge_rd
ge_sub: ld b,(hl)               ; the cluster of entry idx
        dec hl
        ld c,(hl)
        ld (cl),bc
        ld a,(spc)              ; entries per cluster = spc * 16
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld (epc),hl
        ld hl,(tidx)
ge1:    ld de,(epc)
        or a
        sbc hl,de
        jr c,ge2
        push hl
        ld hl,(cl)
        call fatnext
        ld (cl),hl
        ld de,0FF0h
        or a
        sbc hl,de
        pop hl
        ccf
        ret c                   ; end of the chain
        jr ge1
ge2:    add hl,de               ; HL = entry in this cluster
        push hl
        ld hl,(cl)
        call clsec
        ld (secb),hl
        pop hl
ge_rd:  ld a,l                  ; sector + idx / 16, offset (idx and 15) * 32
        and 0Fh
        ld e,a
        ld d,0
        ld b,5
ge3:    sla e
        rl d
        djnz ge3
        ld b,4
ge4:    srl h
        rr l
        djnz ge4
        push de
        ld de,(secb)
        add hl,de
        call rdsec
        pop de
        ld hl,SECBUF
        add hl,de
        ld de,ent
        ld bc,32
        ldir
        or a                    ; no carry
        ret

; ---- pointers to the cluster / index of the current level -----------
curcl:  ld hl,dcl
        jr cur1
curidx: ld hl,didx
cur1:   ld a,(lvl)
        add a,a
        ld e,a
        ld d,0
        add hl,de
        ret

; ---- first sector of cluster HL: datasec + (HL - 2) * spc -----------
clsec:  dec hl
        dec hl
        ld a,(spc)
cs1:    rra
        jr c,cs2
        add hl,hl
        jr cs1
cs2:    ld de,(datasec)
        add hl,de
        ret

; ---- FAT12: next cluster of HL -----------------------------------------
fatnext:
        push de
        ld e,l
        ld d,h
        srl d
        rr e                    ; HL / 2
        push hl
        add hl,de
        ld de,FATBUF
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        pop hl
        bit 0,l
        ex de,hl
        jr z,fn1
        ld b,4
fn0:    srl h
        rr l
        djnz fn0
fn1:    ld a,h
        and 0Fh
        ld h,a
        pop de
        ret

; ---- sector HL of the disk in SECBUF -----------------------------------
rdsec:  ld de,(cursec)          ; already there?
        or a
        sbc hl,de
        add hl,de
        ret z
        ld (cursec),hl
        ld a,(comp)
        or a
        jr nz,rd_c
        ld de,0                 ; plain: base + HL * 512
        call secpos
        call fseek
        ld de,SECBUF
        ld hl,512
        jp fread
rd_c:   ld e,l                  ; compressed: table entry at 4000h + HL * 5
        ld d,h
        xor a                   ; A:HL = HL * 5 + 4000h
        add hl,hl
        adc a,a
        add hl,hl
        adc a,a
        add hl,de
        adc a,0
        ld de,4000h
        add hl,de
        adc a,0
        ld (pos),hl
        ld (pos+2),a
        xor a
        ld (pos+3),a
        call fseek
        ld de,rec
        ld hl,5
        call fread
        xor a                   ; pos = bank * 2000h + address - 4000h
        ld (pos),a
        ld (pos+3),a
        ld a,(rec)
        rrca
        rrca
        rrca
        ld b,a
        and 1Fh
        ld (pos+2),a
        ld a,b
        and 0E0h
        ld (pos+1),a
        ld hl,(rec+1)
        ld de,-4000h
        add hl,de
        ld de,(pos)
        add hl,de
        ld (pos),hl
        ld a,(pos+2)
        adc a,0
        ld (pos+2),a
        call fseek
        ld hl,(rec+3)           ; length
        ld de,512
        or a
        sbc hl,de
        jr nz,rd_p
        ld de,SECBUF            ; stored
        ld hl,512
        jp fread
rd_p:   ld de,CBUF              ; packed
        ld hl,(rec+3)
        call fread
        ld hl,CBUF
        ld de,SECBUF
        di
        call bbdep
        ei
        ret

; ---- BitBuster depacker (as in the DSK2ROM 0.80 driver, 76B8h) -----------
; HL = packed data, DE = destination
bbdep:  ld iy,bb_main
        ld a,80h
        exx
        ld de,1
        exx
bb_lit: ldi
bb_main: add a,a
        jp nz,bb_1
        ld a,(hl)
        inc hl
        rla
bb_1:   jr nc,bb_lit
        exx
        ld l,e
        ld h,d
bb_gam: add a,a
        call z,bb_getx
        jr nc,bb_len
        add a,a
        call z,bb_getx
        adc hl,hl
        jp nc,bb_gam
        exx
        ret
bb_len: inc hl
        exx
        ld c,(hl)
        inc hl
        ld b,0
        bit 7,c
        jp z,bb_off
        add a,a
        call z,bb_get
        rl b
        add a,a
        call z,bb_get
        jr nc,bb_off
        or a
        inc b
        res 7,c
bb_off: inc bc
        push hl
        exx
        push hl
        exx
        ld l,e
        ld h,d
        sbc hl,bc
        pop bc
        ldir
        pop hl
        jp (iy)
bb_get: ld a,(hl)
        inc hl
        rla
        ret
bb_getx: exx
        ld a,(hl)
        inc hl
        exx
        rla
        ret

; ---- pos = base + HL * 512 + DE ------------------------------------
secpos: add hl,hl
        ld a,0
        adc a,a
        ld (pos+3),a
        ld (pos+1),hl
        xor a
        ld (pos),a
        ld hl,(pos)
        add hl,de
        ld (pos),hl
        ld hl,(pos+2)
        ld de,0
        adc hl,de
        ld (pos+2),hl
        ld hl,(pos)
        ld de,(base)
        add hl,de
        ld (pos),hl
        ld hl,(pos+2)
        ld de,(base+2)
        adc hl,de
        ld (pos+2),hl
        ret

; ---- seek the ROM file to HL (< 64 KB) or to pos; read HL bytes to DE ---
seek16: ld (pos),hl
        ld hl,0
        ld (pos+2),hl
fseek:  ld a,(hrom)
        ld b,a
        ld de,(pos+2)
        ld hl,(pos)
        xor a
        ld c,4Ah                ; _SEEK from the start
        jp BDOS
fread:  ld a,(hrom)
        ld b,a
        ld c,48h                ; _READ
        jp BDOS

; ---- ent name to name (ASCIIZ, NAME.EXT) -----------------------------
mkname: ld hl,ent
        ld de,name
        ld b,8
mn1:    ld a,(hl)
        cp ' '
        jr z,mn2
        ld (de),a
        inc de
mn2:    inc hl
        djnz mn1
        ld a,(name)             ; 05h: E5h as first character
        cp 05h
        jr nz,mn3
        ld a,0E5h
        ld (name),a
mn3:    ld a,(hl)
        cp ' '
        jr z,mn5
        ld a,'.'
        ld (de),a
        inc de
        ld b,3
mn4:    ld a,(hl)
        cp ' '
        jr z,mn5
        ld (de),a
        inc de
        inc hl
        djnz mn4
mn5:    xor a
        ld (de),a
        ret

; ---- dname = file name of fname without path and extension ----------
romdir: ld hl,fname
        ld de,fname             ; DE -> after the last \ or :
rd1:    ld a,(hl)
        or a
        jr z,rd2
        inc hl
        cp 5Ch                  ; \
        jr z,rd1a
        cp ':'
        jr nz,rd1
rd1a:   ld e,l
        ld d,h
        jr rd1
rd2:    ex de,hl
        ld de,dname
        ld b,8
rd3:    ld a,(hl)
        or a
        jr z,rd4
        cp '.'
        jr z,rd4
        ld (de),a
        inc hl
        inc de
        djnz rd3
rd4:    xor a
        ld (de),a
        ret

; ---- next argument of the command line at HL to DE (ASCIIZ) ----------
arg:    ld a,(hl)
        cp ' '
        jr z,arg0
        cp 9
        jr nz,arg1
arg0:   inc hl
        jr arg
arg1:   ld a,(hl)
        or a
        jr z,arg2
        cp 13
        jr z,arg2
        cp ' '
        jr z,arg2
        cp 9
        jr z,arg2
        ld (de),a
        inc hl
        inc de
        jr arg1
arg2:   xor a
        ld (de),a
        ret

; ---- messages ------------------------------------------------------
usage:  ld de,m_usage
        jp puts
ferr:   ld de,m_ferr
        jp puts
nodisk: ld de,m_nodisk
        jp puts
toobig: ld de,m_toobig
        jp puts
derr:   ld de,m_derr
        jp puts
werr:   ld de,m_werr
        jp puts
deep:   ld de,m_deep
        jp puts

pdec:   ld b,0                  ; HL in decimal
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
        jp putc
pdec1:  ld a,'0'-1
pdec2:  inc a
        add hl,de
        jr c,pdec2
        sbc hl,de
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

putz:   ld a,(hl)               ; ASCIIZ at HL
        or a
        ret z
        call putc
        inc hl
        jr putz

puts:   push af
        push bc
        push hl
        ld c,09h
        call BDOS
        pop hl
        pop bc
        pop af
        ret

m_title: db "DSK2DIR: disk image of a ROM to a directory",13,10,'$'
m_usage: db "Usage: DSK2DIR file.ROM [directory] (default: the ROM name)",13,10,'$'
m_ferr:  db "Cannot open the ROM file.",13,10,'$'
m_nodisk: db "No disk image found.",13,10,'$'
m_toobig: db "FAT larger than 16 KB (not FAT12).",13,10,'$'
m_derr:  db "Cannot create / enter the directory.",13,10,'$'
m_werr:  db "Write error (disk full?).",13,10,'$'
m_deep:  db "Directories too deep.",13,10,'$'
m_found: db "Disk image at $"
m_comp:  db "Compressed DSK2ROM disk$"
m_sect:  db ", sectors $"
m_done:  db "Done.",13,10,'$'
m_crlf:  db 13,10,'$'
m_up:    db "..",0
m_d2r:   db "DSK2ROM"

hrom:   db 0
hout:   db 0
spc:    db 0
lvl:    db 0
comp:   db 0
secl:   db 0
base:   ds 4
pos:    ds 4
fsize:  ds 4
rec:    ds 5
fatsec: dw 0
spf:    dw 0
rootsec: dw 0
rootent: dw 0
datasec: dw 0
totsec: dw 0
count:  dw 0
cl:     dw 0
epc:    dw 0
secb:   dw 0
secn:   dw 0
tidx:   dw 0
cursec: dw 0
dcl:    ds MAXLVL*2
didx:   ds MAXLVL*2
ent:    ds 32
name:   ds 16
fname:  ds 64
dname:  ds 64
cwd:    ds 66
