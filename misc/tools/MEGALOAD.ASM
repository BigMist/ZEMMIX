; MEGALOAD.COM: loads a MegaROM as it is into the ZEMMIX cartridge RAM of
; slot 1 / slot 2 and reboots, MSX-DOS 2 / Nextor.
; Assemble: pasmo MEGALOAD.ASM MEGALOAD.COM
;
; Usage: MEGALOAD file.ROM [/K | /4 | /A | /1] [/N]
;        MEGALOAD collection.ROM /L          list the games
;        MEGALOAD collection.ROM /G:n [/N]   load game n
;        MEGALOAD collection.ROM /C [/N]     the whole collection, its menu
;        MEGALOAD file.ROM /CK or /CY [/N]   any ROM for the KUC / Yamanooto
;                                            mapper (Pampas & Selene)
;   /C  Konami Ultimate Collection (up to 8 MB) into slot 1 in its KUC mode
;       (OSD Slot1 MegaSCC+ 2MB and Slot1 ROM type KUC 8MB; 32 MB SDRAM):
;       the cartridge as it is, with its menu
;   /K  Konami SCC: MegaSCC+ of slot 1 (OSD Slot1 MegaSCC+ 2MB), up to 2 MB
;   /4  Konami without SCC: slot 1 too, in its Konami mode (7FFEh bit 5,
;       cores from 2026-10-11), up to 2 MB
;   /A  ASCII 8 kB: slot 2 (OSD Slot2 MegaRAM 1MB/1MB), up to 1 MB
;   /1  ASCII 16 kB: slot 2 (OSD Slot2 MegaRAM 2MB/2MB), up to 2 MB
;   /N  load only, back to DOS
; Without /K /4 /A /1 the mapper is guessed from the LD (nnnn),A of the
; ROM to the bank registers (as openMSX does).  MEGALOAD never changes the
; ROM.
; Collections: Konami Neo-Ultimate Collection (SMX Team, Yamanooto
; cartridge, 8 MB).  Its menu table at 0010h: per game a word (high byte
; type: 1 16 kB, 2 32 kB, 4 Konami, 5 Konami SCC; low byte: start in 32 kB
; units) and the name (ASCIIZ).  A game ends where the next one starts.  A
; 16 kB game is mirrored at 8000h (SCC banks 0 / 1 there too).
; A disk converted to a ROM (DSK2ROM): Nextor (slot 3-2 in ZEMMIX) would
; boot instead of the disk of the ROM, as openMSX does with Nextor in 3-2,
; so the reboot sets the Nextor one-time boot key N (NEXTOR_BOOT_KEYS at
; A100h, N = bit 7 of A113h): the Nextor kernel is off for that boot only.
;
; Cartridge RAM (misc/megaram.vhd):
;   SCC     7FFEh bit 4 = 1: RAM writable at 4000h-7FFDh, the bank registers
;           off; 5000h = bank of 4000h-5FFFh
;   ASCII   a bank with bit 7 = 1 is writable; 7000h = 8 kB bank of 8000h
;           (ASCII 8) or 16 kB bank of 8000h-BFFFh (ASCII 16, bit 6 = bit 6
;           of the bank)
; Before loading, the slot is checked: two banks written and read back.
; When loading into slot 2 a ROM left in the MegaSCC+ of slot 1 would boot
; first, so its "AB" is cleared (only if slot 1 is RAM).

BDOS    equ 5
ENASLT  equ 0024h
CALSLT  equ 001Ch
RAMAD1  equ 0F342h
RAMAD2  equ 0F343h
EXPTBL  equ 0FCC1h
BUF     equ 2000h               ; 8 kB in page 0
KBUF    equ 8000h               ; 16 kB in page 2: the start of a collection
KBUFEND equ 0BFh                ; high byte of the end of KBUF
T_SCC   equ 1
T_ASC8  equ 2
T_ASC16 equ 3
T_KON   equ 4

        org 100h

start:  ld de,m_title
        call puts
        ld hl,81h
        ld de,fname
        call arg
        ld a,(fname)
        or a
        jp z,usage
opts:   ld de,opt               ; options
        call arg
        ld a,(opt)
        or a
        jp z,opend
        ld a,(opt+1)
        and 0DFh
        cp 'L'
        jr nz,opg
        ld a,1                  ; /L: list a collection
        ld (cmode),a
        jr opts
opg:    cp 'C'
        jr nz,opg0
        ld a,3                  ; /C: a whole collection (KUC mode)
        ld (cmode),a
        ld a,(opt+2)            ; /CK, /CY: that mapper, any ROM
        and 0DFh
        ld b,2
        cp 'K'
        jr z,opc1
        dec b
        cp 'Y'
        jp nz,opts
opc1:   ld a,b
        ld (cforce),a
        jp opts
opg0:   cp 'G'
        jr nz,op4
        ld a,2                  ; /G:n: game n of a collection
        ld (cmode),a
        push hl
        ld hl,opt+2
        ld a,(hl)
        cp ':'
        jr nz,opg1
        inc hl
opg1:   ld b,0                  ; decimal number to B
opg2:   ld a,(hl)
        sub '0'
        jr c,opg3
        cp 10
        jr nc,opg3
        ld c,a
        ld a,b
        add a,a
        add a,a
        add a,b
        add a,a
        add a,c
        ld b,a
        inc hl
        jr opg2
opg3:   ld a,b
        ld (gnum),a
        pop hl
        jr opts
op4:    ld a,(opt+1)
        cp '4'
        jr nz,opn
        ld a,T_KON
        ld (rtype),a
        jr opts
opn:    ld a,(opt+1)
        and 0DFh
        cp 'N'
        jr nz,op0
        ld a,1
        ld (noboot),a
        jp opts
op0:
op1:    ld b,T_SCC
        cp 'K'
        jr z,op2
        ld b,T_ASC8
        cp 'A'
        jr z,op2
        ld b,T_ASC16
        ld a,(opt+1)
        cp '1'
        jp nz,usage
op2:    ld a,b
        ld (rtype),a
        jp opts
opend:  ld de,fname
        xor a
        ld c,43h                ; _OPEN
        call BDOS
        or a
        jp nz,ferr
        ld a,b
        ld (handle),a
        ld a,(cmode)
        or a
        jp nz,coll
        call isdsk              ; a disk in a ROM (DSK2ROM)?
        jr nz,nodsk
        ld a,1
        ld (isdisk),a
        ld de,m_disk
        call puts
        ld a,(handle)           ; back to the start of the file
        ld b,a
        ld de,0
        ld hl,0
        xor a
        ld c,4Ah
        call BDOS
nodsk:
        ld a,(rtype)
        or a
        call z,guess
nodsk2: ld a,(rtype)
        or a
        jp z,unknown

        ld a,(rtype)            ; slot and size limit
        ld de,m_scc
        ld b,01h
        ld c,0                  ; 256 blocks of 8 kB
        cp T_SCC
        jr z,ty1
        ld de,m_kon
        cp T_KON
        jr z,ty1
        ld de,m_asc8
        ld b,02h
        ld c,128
        cp T_ASC8
        jr z,ty1
        ld de,m_asc16
        ld c,0
ty1:    ld a,b
        ld (slot),a
        ld a,c
        ld (maxblk),a
        call puts

        call probe              ; is the slot in that mode?
        jr nz,nopr
        ld a,(rtype)            ; Konami: has the core its Konami mode?
        cp T_KON
        jr nz,prok
        call kprobe
        jr z,prok
        ld de,m_nokon
        jp puts
nopr:
        ld de,m_noslot
        call puts
        ld a,(rtype)            ; which OSD setting it needs
        ld de,m_need1
        cp T_SCC
        jr z,nos1
        ld de,m_need8
        cp T_ASC8
        jr z,nos1
        ld de,m_need16
nos1:   jp puts
prok:

        ld a,(slot)             ; slot 2: the ROM of slot 1 must not boot
        cp 2
        call z,clr1

        xor a
        ld (block),a
blk:    ld a,(clim)             ; a game of a collection: its size
        or a
        jr z,blk0
        ld b,a
        ld a,(block)
        cp b
        jp z,loaded
blk0:   ld a,(handle)           ; next 8 kB
        ld b,a
        ld de,BUF
        ld hl,2000h
        ld c,48h                ; _READ
        call BDOS
        ld a,h
        or l
        jr z,loaded
        ld (count),hl
        ld a,(maxblk)           ; too big?
        or a
        jr z,blk1
        ld b,a
        ld a,(block)
        cp b
        jp nc,toobig
blk1:   call cart
        call isk
        jr nz,blk2
        xor a                   ; SCC: through 4000h
        ld (7FFEh),a
        ld a,(block)
        ld (5000h),a
        ld a,10h
        ld (7FFEh),a
        ld de,4000h
        call copy
        xor a
        ld (7FFEh),a
        jr blk4
blk2:   cp T_ASC8
        jr nz,blk3
        ld a,(block)            ; ASCII 8: through 8000h
        or 80h
        ld (7000h),a
        ld de,8000h
        call copy
        jr blk4
blk3:   ld a,(block)            ; ASCII 16: 16 kB bank = block / 2
        srl a
        or 80h
        ld (7000h),a
        ld de,8000h
        ld a,(block)
        rra
        jr nc,blk3a
        ld de,0A000h
blk3a:  call copy
blk4:   call ram
        ld a,'.'
        call putc
        ld a,1
        ld (nblk),a
        ld a,(block)
        inc a
        ld (block),a
        jp nz,blk

loaded: ld a,(handle)
        ld b,a
        ld c,45h
        call BDOS
        ld de,m_crlf
        call puts
        ld a,(nblk)
        or a
        jp z,ferr

        call cart               ; bank registers as at power on
        call isk
        jr nz,ld2
        xor a
        ld (7FFEh),a
        ld (5000h),a
        inc a
        ld (7000h),a
        inc a
        ld (9000h),a
        inc a
        ld (0B000h),a
        ld a,(mirror)           ; 16 kB game: also at 8000h
        or a
        jr z,ld1
        xor a
        ld (9000h),a
        inc a
        ld (0B000h),a
        ld a,(mirror)           ; 8 kB game: everywhere
        cp 2
        jr nz,ld1
        xor a
        ld (7000h),a
        ld (0B000h),a
ld1:    ld a,(rtype)            ; Konami: its mode (7FFEh bit 5)
        cp T_KON
        jr nz,ld3
        ld a,20h
        ld (7FFEh),a
        jr ld3
ld2:    xor a                   ; ASCII 8 / 16: all 0
        ld (6000h),a
        ld (6800h),a
        ld (7000h),a
        ld (7800h),a
ld3:    call ram

        ld a,(noboot)
        or a
        jr z,boot
        ld de,m_loaded
        call puts
        ld a,(isdisk)
        or a
        ret z
        ld de,m_keyn
        jp puts
boot:   ld a,(isdisk)           ; a disk: Nextor off for this boot (key N)
        or a
        jr z,boot1
        ld hl,m_nbk
        ld de,0A100h
        ld bc,m_nbk_e-m_nbk
        ldir
boot1:  ld de,m_boot
        call puts
        ld iy,(EXPTBL-1)        ; 0000h of the main ROM: the BIOS reset
        ld ix,0000h
        jp CALSLT

; ---- guess the mapper: LD (nnnn),A to the bank registers ---------------
; Counted per register group: SCC 5000h/9000h/B000h, ASCII 8 6800h/7800h,
; Konami 8000h/A000h (only theirs), shared 6000h/7000h/77FFh.  Scores with
; the share of the writes of each mapper that only it has: SCC 8 * (3 of
; its 4 registers), ASCII 8 12 * (2 of 4), Konami 9 * (2 of 3), ASCII 16
; 6 * shared (it has none of its own).  The largest wins.
guess:  ld hl,0
        ld (c_scc),hl
        ld (c_a8),hl
        ld (c_kon),hl
        ld (c_sh),hl
gs_blk: ld a,(glim)             ; a game of a collection: only its blocks
        or a
        jr z,gs_b1
        dec a
        jr z,gs_end
        ld (glim),a
gs_b1:  ld a,(handle)
        ld b,a
        ld de,BUF
        ld hl,2000h
        ld c,48h
        call BDOS
        ld a,h
        or l
        jr z,gs_end
        ld b,h                  ; BC = bytes, HL -> data
        ld c,l
        ld hl,BUF
gs1:    ld a,(hl)
        cp 32h                  ; LD (nnnn),A
        jr nz,gs9
        push hl
        push bc
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        call gscnt
        pop bc
        pop hl
gs9:    inc hl
        dec bc
        ld a,b
        or c
        jr nz,gs1
        jr gs_blk
gs_end: ld a,(handle)           ; back to the start of the file
        ld b,a
        ld de,0
        ld hl,0
        xor a
        ld c,4Ah                ; _SEEK
        call BDOS
gs_sc:  ld hl,(c_scc)           ; scores
        ld a,8
        call mul
        ld (s_scc),hl
        ld hl,(c_a8)
        ld a,12
        call mul
        ld (s_a8),hl
        ld hl,(c_kon)
        ld a,9
        call mul
        ld (s_kon),hl
        ld hl,(c_sh)
        ld a,6
        call mul
        ld (s_a16),hl
        ld hl,(s_scc)           ; the largest; ties: SCC, ASCII 8, 16, Konami
        ld b,T_SCC
        ld de,(s_a8)
        ld c,T_ASC8
        call gsmax
        ld de,(s_a16)
        ld c,T_ASC16
        call gsmax
        ld de,(s_kon)
        ld c,T_KON
        call gsmax
        ld a,h
        or l
        ret z                   ; nothing found: unknown
        ld a,b
        ld (rtype),a
        ret
gsmax:  push hl                 ; HL = best, B = its type; DE, C = candidate
        or a
        sbc hl,de
        pop hl
        ret nc
        ex de,hl
        ld b,c
        ret
mul:    ld e,l                  ; HL = HL * A (saturated)
        ld d,h
        ld hl,0
mu1:    add hl,de
        jr c,mu2
        dec a
        jr nz,mu1
        ret
mu2:    ld hl,0FFFFh
        ret
; DE = address written: count it
gscnt:  ld a,e
        cp 0FFh
        jr nz,gc0
        ld a,d
        cp 77h
        ret nz
        ld hl,c_sh              ; 77FFh
        jr inc16
gc0:    or a
        ret nz                  ; only xx00h
        ld a,d
        ld hl,c_scc
        cp 50h
        jr z,inc16
        cp 90h
        jr z,inc16
        cp 0B0h
        jr z,inc16
        ld hl,c_a8
        cp 68h
        jr z,inc16
        cp 78h
        jr z,inc16
        ld hl,c_kon
        cp 80h
        jr z,inc16
        cp 0A0h
        jr z,inc16
        ld hl,c_sh
        cp 60h
        jr z,inc16
        cp 70h
        ret nz
inc16:  inc (hl)
        ret nz
        inc hl
        inc (hl)
        ret

; ---- Z if the file is a DSK2ROM disk ("DSK2ROM" at 3FE0h) -------------
isdsk:  ld a,(handle)
        ld b,a
        ld de,BUF
        ld hl,4000h-2000h       ; skip the first 8 kB
        ld c,48h
        call BDOS
        ld a,(handle)
        ld b,a
        ld de,BUF
        ld hl,2000h             ; 2000h-3FFFh
        ld c,48h
        call BDOS
        ld a,h
        cp 20h
        jr nz,isd9
        ld hl,BUF+1FE0h
        ld de,m_dsk2rom
        ld b,7
isd1:   ld a,(de)
        cp (hl)
        jr nz,isd9
        inc hl
        inc de
        djnz isd1
        xor a                   ; Z: it is one
        ret
isd9:   ld a,(handle)           ; no: back to the start of the file
        ld b,a
        ld de,0
        ld hl,0
        xor a
        ld c,4Ah
        call BDOS
        or 1                    ; NZ
        ret

; ---- the slot works in the mode wanted? NZ if not ----------------------
; bank 1 = 5Ah, bank 2 = A5h, bank 1 read back
probe:  call cart
        ld a,1
        ld e,5Ah
        call pwr
        ld a,2
        ld e,0A5h
        call pwr
        ld a,1
        call prd
        ld (pr_1),a
        ld a,2
        call prd
        ld (pr_2),a
        call ram                ; ENASLT changes every register
        ld a,(pr_1)
        cp 5Ah
        ret nz
        ld a,(pr_2)
        cp 0A5h
        ret
pwr:    ld b,a                  ; write E at the start of block A
        call isk
        jr nz,pw1
        xor a
        ld (7FFEh),a
        ld a,b
        ld (5000h),a
        ld a,10h
        ld (7FFEh),a
        ld a,e
        ld (4000h),a
        xor a
        ld (7FFEh),a
        ret
pw1:    ld a,b
        or 80h
        ld (7000h),a
        ld a,e
        ld (8000h),a
        ret
prd:    ld d,a                  ; read the start of block A
        call isk
        jr nz,pr1
        xor a
        ld (7FFEh),a
        ld a,d
        ld (5000h),a
        ld a,(4000h)
        ret
pr1:    ld a,d
        ld (7000h),a
        ld a,(8000h)
        ret

; ---- Z if the type uses the MegaSCC+ of slot 1 (Konami SCC or Konami) --
isk:    ld a,(rtype)
        cp T_SCC
        ret z
        cp T_KON
        ret

; ---- Konami mode there?  After probe: block 1 = 5Ah, 2 = A5h.  In the
; Konami mode 8000h is a bank register: bank 1 there must read 5Ah.  NZ if not
kprobe: call cart
        ld a,20h
        ld (7FFEh),a
        ld a,1
        ld (8000h),a
        ld a,(8000h)
        ld (pr_1),a
        xor a
        ld (7FFEh),a
        call ram
        ld a,(pr_1)
        cp 5Ah
        ret

; ---- collections ---------------------------------------------------------
; The first 16 kB of the file in KBUF (page 2, still RAM here).
; Neo-Ultimate (ckind 1): table at 0010h, see the header.
; Konami Ultimate Collection (ckind 2, Manuel Pazos: 2014 and Enhanced 1.6):
; found through the code of its launcher.  Sizes in 8 kB banks (LD B,n /
; LD DE,sizes / LD HL,C0xxh / LD A,1 / EX DE,HL / ADD A,(HL)): game m starts
; at bank 1 + the sizes before it.  The menu item i is game map[i] (LD
; HL,map / CALL 4010h / LD A,(HL) / DEC A / RLCA).  Names: 28 bytes each
; from "RC700".  The mapper goes by the menu item (rules14 / rules16: the
; 1.6 has CP 5Bh there).
coll:   ld a,(cmode)
        cp 3
        jp z,cfull
        ld a,(handle)
        ld b,a
        ld de,KBUF
        ld hl,4000h
        ld c,48h
        call BDOS
        call cparse
        ld a,1
        jr z,coll1
        call kfind
        jp nz,notcoll
        ld a,2
coll1:  ld (ckind),a
        ld a,(cmode)
        cp 1
        jp z,clist
        ld a,(gnum)             ; game n (1-based)
        or a
        jp z,badnum
        ld b,a
        ld a,(ncoll)
        cp b
        jp c,badnum
        ld a,(ckind)
        cp 2
        jp z,kgame
        ld a,b
        call crec               ; HL -> its record
        ld a,(hl)
        ld (gpos),a
        inc hl
        ld a,(hl)
        ld (gtype),a
        inc hl
        call pname
        ld de,m_crlf
        call puts
        ld a,(gpos)             ; its end: the next start, or the file end
        ld c,a
        ld b,0                  ; B = next start (0 = 256)
        ld a,(ncoll)
        ld e,a
        ld hl,KBUF+10h
cg1:    ld a,(hl)
        cp c
        jr z,cg2
        jr c,cg2
        ld d,a                  ; start > ours: the smallest
        ld a,b
        or a
        jr z,cg1a
        ld a,d
        cp b
        jr nc,cg2
cg1a:   ld b,d
cg2:    call cskip
        dec e
        jr nz,cg1
        ld a,b                  ; size in 32 kB units, x4 = 8 kB blocks
        sub c
        add a,a
        add a,a
        ld (clim),a
        ld a,(gtype)
        ld b,T_SCC
        cp 1
        jr nz,cg3
        ld a,2                  ; 16 kB, mirrored
        ld (clim),a
        ld a,1
        ld (mirror),a
        jr cg5
cg3:    cp 2
        jr nz,cg4
        ld a,4                  ; 32 kB
        ld (clim),a
        jr cg5
cg4:    cp 5
        jr z,cg5
        ld b,T_KON
cg5:    ld a,b
        ld (rtype),a
        ld a,(gpos)             ; bank = 32 kB units x 4
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        ld (gbank),hl
        jp cseek

kgame:  ld a,b                  ; KUC: menu item n - 1
        dec a
        ld (gidx),a
        call kname
        call pname22
        ld de,m_crlf
        call puts
        ld a,(gidx)
        call kentry
        call kstart             ; HL = first bank, A = banks
        ld (gbank),hl
        ld (clim),a
        ld a,(gidx)
        call ktype
        or a
        jr z,kg0
        ; a MegaROM: Konami or Konami SCC by its code (the launcher runs both
        ; in its own Konami mode, which switches 4000h too and has the SCC)
        ld (gtype),a
        call cseek0
        ld a,(clim)
        inc a
        ld (glim),a
        xor a
        ld (rtype),a
        call guess
        ld a,(rtype)
        cp T_SCC
        jr z,kg2
        cp T_KON
        jr z,kg2
        ld a,(gtype)            ; not found: as the launcher says
        jr kg2
kg0:
        ld a,(clim)             ; a plain ROM: mirrored when < 32 kB
        ld b,2
        cp 1
        jr z,kg1
        dec b
        cp 2
        jr nz,kg1a
kg1:    ld a,b
        ld (mirror),a
kg1a:   ld a,T_SCC
kg2:    ld (rtype),a

cseek:  call cseek0
        jp nodsk2
cseek0: ld de,(gbank)           ; seek: bank * 8 kB = DE:HL
        ld a,e
        and 7
        rrca
        rrca
        rrca
        ld h,a
        ld l,0
        srl d
        rr e
        srl d
        rr e
        srl d
        rr e
        ld a,(handle)
        ld b,a
        xor a
        ld c,4Ah
        jp BDOS

clist:  ld a,(ncoll)
        ld (cnt),a
        ld hl,KBUF+10h
        ld c,1
cl1:    push hl
        push bc
        ld a,c
        call pdec
        ld a,' '
        call putc
        ld a,(ckind)
        cp 2
        jr z,cl3
        inc hl
        ld a,(hl)               ; type
        ld de,m_t16
        cp 1
        jr z,cl2
        ld de,m_t32
        cp 2
        jr z,cl2
        ld de,m_tk4
        cp 4
        jr z,cl2
        ld de,m_tscc
cl2:    call puts
        inc hl
        call pname
        jr cl5
cl3:    ld a,c                  ; KUC: item c - 1
        dec a
        ld (gidx),a
        call ktype
        ld de,m_tmeg
        or a
        jr nz,cl4
        ld a,(gidx)             ; plain: by its size
        call kentry
        call kstart
        ld de,m_t8
        cp 1
        jr z,cl4
        ld de,m_t16
        cp 2
        jr z,cl4
        ld de,m_t32
cl4:    call puts
        ld a,(gidx)
        call kname
        call pname22
cl5:    ld de,m_crlf
        call puts
        pop bc
        pop hl
        ld a,(ckind)
        cp 2
        call nz,cskip
        inc c
        ld a,(cnt)
        dec a
        ld (cnt),a
        jp nz,cl1
        ld a,(handle)
        ld b,a
        ld c,45h
        jp BDOS

; Z and (ncoll) if KBUF holds a Neo-Ultimate table: "AB" and 10+ records
cparse: ld a,(KBUF)
        cp 'A'
        ret nz
        ld a,(KBUF+1)
        cp 'B'
        ret nz
        ld hl,KBUF+10h
        ld c,0
cp1:    inc hl
        ld a,(hl)
        dec hl
        cp 1
        jr z,cp2
        cp 2
        jr z,cp2
        cp 4
        jr z,cp2
        cp 5
        jr nz,cp9
cp2:    inc c
        call cskip
        ld a,h                  ; inside the 8 kB
        cp KBUFEND
        jr c,cp1
cp9:    ld a,c
        ld (ncoll),a
        cp 10
        jr c,cpno
        xor a
        ret
cpno:   or 1
        ret
; HL -> record: skip it (word and name)
cskip:  inc hl
        inc hl
cs1:    ld a,(hl)
        inc hl
        or a
        jr nz,cs1
        ret
; A = n (1-based): HL -> record n
crec:   ld hl,KBUF+10h
cr1:    dec a
        ret z
        push af
        call cskip
        pop af
        jr cr1

; ---- KUC: Z and (ncoll), (sztab), (maptab), (names), (krules) if found --
kfind:  ld ix,pat_sz
        call kscan
        ret nz
        inc hl
        ld a,(hl)
        ld (nsz),a
        inc hl
        inc hl
        call kaddr
        ld (sztab),hl
        ld ix,pat_map
        call kscan
        ret nz
        inc hl
        call kaddr
        ld (maptab),hl
        ld ix,pat_name
        call kscan
        ret nz
        ld (names),hl
        ld ix,pat_16
        call kscan
        ld hl,rules14
        jr nz,kf1
        ld hl,rules16
kf1:    ld (krules),hl
        ld hl,(maptab)          ; items: while item < nsz and map[item] < nsz
        ld c,0
        ld a,(nsz)
        ld b,a
kf2:    ld a,c
        cp b
        jr nc,kf3
        ld a,(hl)
        cp b
        jr nc,kf3
        inc hl
        inc c
        jr kf2
kf3:    ld a,c
        ld (ncoll),a
        cp 10
        jr c,kfno
        xor a
        ret
kfno:   ld a,1
        or a
        ret
; the word at HL, a ROM address (4000h-7FFFh), as an address in KBUF
kaddr:  ld e,(hl)
        inc hl
        ld d,(hl)
        ld hl,KBUF-4000h
        add hl,de
        ret
; the pattern at IX (length, bytes, FFh = any) in KBUF: Z and HL, or NZ
kscan:  ld hl,KBUF
        ld bc,3FF0h
ks0:    push hl
        push bc
        push ix
        pop de
        ld a,(de)
        ld b,a
        inc de
ks1:    ld a,(de)
        cp 0FFh
        jr z,ks2
        cp (hl)
        jr nz,ks3
ks2:    inc hl
        inc de
        djnz ks1
        pop bc
        pop hl
        xor a
        ret
ks3:    pop bc
        pop hl
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,ks0
        inc a
        ret
; A = menu item: A = its game (map)
kentry: ld hl,(maptab)
        ld e,a
        ld d,0
        add hl,de
        ld a,(hl)
        ret
; A = game: HL = its first bank (1 + the sizes before), A = its size
kstart: ld b,a
        ld de,(sztab)
        ld hl,1
        or a
        jr z,kst2
kst1:   ld a,(de)
        add a,l
        ld l,a
        jr nc,kst1a
        inc h
kst1a:  inc de
        djnz kst1
kst2:   ld a,(de)
        ret
; A = menu item: A = its mapper (0 plain, T_KON, T_SCC) from the rules
ktype:  ld c,a
        ld hl,(krules)
        ld b,0
kt1:    ld a,(hl)
        cp 0FFh
        jr z,kt9
        ld a,c
        cp (hl)
        jr c,kt9
        inc hl
        ld b,(hl)
        inc hl
        jr kt1
kt9:    ld a,b
        ret
; A = menu item: HL -> its name (names + 28 * item)
kname:  ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        ld d,h
        ld e,l
        add hl,hl
        add hl,hl
        add hl,hl
        or a
        sbc hl,de
        ld de,(names)
        add hl,de
        ret
; 22 characters at HL ("@" is "-" in the KUC names)
pname22: ld b,22
pn22:   ld a,(hl)
        cp '@'
        jr nz,pn22a
        ld a,'-'
pn22a:  call putc
        inc hl
        djnz pn22
        ret
pat_sz:   db 12, 06h,0FFh,11h,0FFh,0FFh,21h,0FFh,0C0h,3Eh,01h,0EBh,86h
pat_map:  db 9, 21h,0FFh,0FFh,0CDh,10h,40h,7Eh,3Dh,07h
pat_name: db 5, "RC700"
pat_16:   db 3, 0FEh,5Bh,30h
; first menu item, mapper (from the launchers): FFh ends
rules14:  db 00h,0, 24h,T_KON, 33h,T_SCC, 39h,T_KON, 3Ah,T_SCC, 0FFh
rules16:  db 00h,0, 24h,T_KON, 33h,T_SCC, 39h,T_KON, 3Ah,T_SCC, 59h,T_KON, 0FFh
; name at HL (ASCIIZ, leading spaces skipped)
pname:  ld a,(hl)
        cp ' '
        jr nz,pn1
        inc hl
        jr pname
pn1:    ld a,(hl)
        or a
        ret z
        call putc
        inc hl
        jr pn1
; A as 3 decimal digits (spaces for leading zeros)
pdec:   ld e,' '
        ld b,100
        call pd1
        ld b,10
        call pd1
        add a,'0'
        jp putc
pd1:    ld d,'0'-1
pd2:    inc d
        sub b
        jr nc,pd2
        add a,b
        push af
        ld a,d
        cp '0'
        jr nz,pd3
        ld a,e
        jr pd4
pd3:    ld e,'0'
pd4:    call putc
        pop af
        ret
;
; ---- /C: the whole file into the KUC memory of slot 1 (ZEMMIX-58x.2) -----
; Block b (8 kB): 7FFFh = A21-A20 (b / 256), 5000h = b mod 256, then 7FFFh
; bits 4, 1, 0 (ZEMMIX raw write, bank switching off) and the 8 kB to
; 4000h-5FFFh.  The registers end as at power on: the menu boots.
cfull:  ld a,(cforce)           ; /CK, /CY: as told
        or a
        jp nz,cfk
        ld a,(handle)           ; a KUC?  (its launcher in the first 16 kB)
        ld b,a
        ld de,KBUF
        ld hl,4000h
        ld c,48h
        call BDOS
        call cparse             ; Neo-Ultimate: Yamanooto mode
        ld a,1
        jr z,cfk
        call kfind              ; KUC: KUC mode
        ld a,2
        jr z,cfk
        ld de,m_onlykuc
        jp puts
cfk:    ld (ckind),a
cfl:    ld a,(handle)           ; back to the start of the file
        ld b,a
        ld de,0
        ld hl,0
        xor a
        ld c,4Ah
        call BDOS
        ld a,1
        ld (slot),a
        ld de,m_kucl
        ld a,(ckind)
        cp 2
        jr z,cfl0a
        ld de,m_yaml
cfl0a:  call puts
        call kucprb
        jr z,cfl0
        ld de,m_nokuc
        ld a,(ckind)
        cp 2
        jp z,puts
        ld de,m_noyam
        jp puts
cfl0:   ld hl,0
        ld (kblk),hl
cfl1:   ld a,(handle)
        ld b,a
        ld de,BUF
        ld hl,2000h
        ld c,48h
        call BDOS
        ld a,h
        or l
        jr z,cfl9
        ld (count),hl
        ld a,(kblk+1)           ; 1024 blocks at most
        cp 4
        jp nc,toobig
        call cart
        ld hl,(kblk)
        call kwblk
        call ram
        ld a,(kblk)             ; a dot every 64 kB
        and 7
        ld a,'.'
        call z,putc
        ld hl,(kblk)
        inc hl
        ld (kblk),hl
        ld a,1
        ld (nblk),a
        jr cfl1
cfl9:   ld a,(handle)
        ld b,a
        ld c,45h
        call BDOS
        ld de,m_crlf
        call puts
        ld a,(nblk)
        or a
        jp z,ferr
        call cart               ; registers as at power on
        ld a,1                  ; Yamanooto: REGEN for 7FFD-7FFEh
        ld (7FFFh),a
        xor a
        ld (7FFDh),a
        ld (7FFEh),a
        ld (7FFFh),a
        ld (5000h),a
        inc a
        ld (7000h),a
        inc a
        ld (9000h),a
        inc a
        ld (0B000h),a
        xor a
        ld (0BFFEh),a
        call ram
        jp ld3

; HL = block: BUF (count bytes) into it (cartridge in pages 1-2)
kwblk:  ld a,(ckind)
        cp 2
        jr nz,ywblk
        ld a,h                  ; A21-A20 in bits 7-6
        rrca
        rrca
        and 0C0h
        ld (khi),a
        ld (7FFFh),a            ; registers on, Konami SCC, switching on
        xor a
        ld (7FFEh),a
        ld a,l
        ld (5000h),a
        ld a,(khi)
        or 13h                  ; raw write, switching off
        ld (7FFFh),a
        ld de,4000h
        call copy
        ld a,(khi)
        ld (7FFFh),a
        ret
; Yamanooto: offset = block / 4 (7FFEh) + block mod 4 (7FFDh bits 5-4),
; 5000h = 0: bank 0 = the block; then ENAR WREN + bit 7 (ZEMMIX raw write)
ywblk:  call yset
        ld a,91h
        ld (7FFFh),a
        ld de,4000h
        call copy
        ld a,1
        ld (7FFFh),a
        ret
yset:   ld a,1                  ; REGEN
        ld (7FFFh),a
        ld a,l
        and 3
        rlca
        rlca
        rlca
        rlca
        ld (7FFDh),a
        ld a,h                  ; HL / 4
        ld e,l
        srl a
        rr e
        srl a
        rr e
        ld a,e
        ld (7FFEh),a
        xor a
        ld (5000h),a
        ret
; HL = block: A = its first byte
krblk:  ld a,(ckind)
        cp 2
        jr z,krk
        call yset
        ld a,(4000h)
        ret
krk:    ld a,h
        rrca
        rrca
        and 0C0h
        ld (7FFFh),a
        xor a
        ld (7FFEh),a
        ld a,l
        ld (5000h),a
        ld a,(4000h)
        ret

; Z if slot 1 is in KUC mode: blocks 0, 1 and 300h written; block 1 read
; through the offset register (bank 0 + offset 1), 300h through A21-A20
kucprb: ld hl,1
        ld (count),hl
        call cart
        ld a,0C3h
        ld (BUF),a
        ld hl,0
        call kwblk
        ld a,5Ah
        ld (BUF),a
        ld hl,1
        call kwblk
        ld a,0A5h
        ld (BUF),a
        ld hl,300h
        call kwblk
        ld a,(ckind)
        cp 2
        jr nz,kpy
        xor a                   ; KUC: bank 0, offset 1: block 1
        ld (7FFFh),a
        ld (5000h),a
        inc a
        ld (7FFEh),a
        ld a,(4000h)
        jr kpy1
kpy:    ld a,1                  ; Yamanooto: offset 0, sub-offset 1, 5000h = 0
        ld (7FFFh),a
        xor a
        ld (7FFEh),a
        ld a,10h
        ld (7FFDh),a
        xor a
        ld (5000h),a
        ld a,(4000h)
kpy1:   ld (pr_1),a
        ld hl,300h
        call krblk
        ld (pr_2),a
        ld a,1
        ld (7FFFh),a
        xor a
        ld (7FFDh),a
        ld (7FFEh),a
        ld (7FFFh),a
        call ram
        ld a,(pr_1)
        cp 5Ah
        ret nz
        ld a,(pr_2)
        cp 0A5h
        ret

notcoll: ld de,m_notcoll
        jp puts
badnum: ld de,m_badnum
        jp puts

; ---- slot 1: clear the "AB" of a ROM left in the MegaSCC+ ---------------
clr1:   di
        ld a,01h
        ld h,40h
        call ENASLT
        di
        xor a
        ld (7FFEh),a
        ld (5000h),a            ; bank 0
        ld a,(4000h)
        cp 'A'
        jr nz,cl9
        ld a,10h                ; MegaSCC+ RAM? 4002h written, read back
        ld (7FFEh),a
        ld a,(4002h)
        ld b,a
        cpl
        ld (4002h),a
        ld a,(4002h)
        cpl
        cp b
        jr nz,cl9               ; not RAM (a real cartridge): left alone
        ld (4002h),a            ; restored
        xor a
        ld (4000h),a
        ld (4001h),a
        ld a,1
        ld (clred),a
cl9:    xor a
        ld (7FFEh),a
        ld a,(RAMAD1)
        ld h,40h
        call ENASLT
        ei
        ld a,(clred)
        or a
        ret z
        ld de,m_clr1
        jp puts

; ---- pages 1 and 2 to the cartridge / back to RAM (interrupts off) -----
cart:   di
        ld a,(slot)
        ld h,40h
        call ENASLT
        di
        ld a,(slot)
        ld h,80h
        call ENASLT
        di
        ret
ram:    ld a,(RAMAD1)
        ld h,40h
        call ENASLT
        ld a,(RAMAD2)
        ld h,80h
        call ENASLT
        ei
        ret

; ---- count bytes of BUF to DE -------------------------------------------
copy:   ld hl,BUF
        ld bc,(count)
        ldir
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

usage:  ld de,m_usage
        jp puts
ferr:   ld de,m_ferr
        jp puts
unknown: ld de,m_unknown
        jp puts
toobig: call ram
        ld de,m_toobig
        jp puts

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
rtype:  db 0
slot:   db 0
maxblk: db 0
block:  db 0
noboot: db 0
isdisk: db 0
nblk:   db 0
clred:  db 0
cmode:  db 0                    ; 1 /L, 2 /G
gnum:   db 0
ncoll:  db 0
cnt:    db 0
gpos:   db 0
gtype:  db 0
clim:   db 0                    ; blocks to load (collection game), 0 = all
mirror: db 0                    ; 1: 16 kB game, 2: 8 kB game
ckind:  db 0                    ; 1 Neo-Ultimate, 2 KUC
glim:   db 0                    ; guess: blocks + 1, 0 = the whole file
kblk:   dw 0                    ; /C: block being loaded
cforce: db 0                    ; /CK 2, /CY 1
khi:    db 0
gidx:   db 0
nsz:    db 0
gbank:  dw 0
sztab:  dw 0
maptab: dw 0
names:  dw 0
krules: dw 0
pr_1:   db 0
pr_2:   db 0
count:  dw 0
c_scc:  dw 0
c_a8:   dw 0
c_kon:  dw 0
c_sh:   dw 0
s_scc:  dw 0
s_a8:   dw 0
s_a16:  dw 0
s_kon:  dw 0
m_title: db "MEGALOAD: MegaROM as it is into the ZEMMIX cartridge RAM",13,10,'$'
m_usage: db "Usage: MEGALOAD file.ROM [/K|/4|/A|/1] [/N]",13,10
         db " /K Konami SCC (slot 1)  /4 Konami (slot 1)",13,10
         db " /A ASCII 8 (slot 2 MegaRAM 1MB/1MB)",13,10
         db " /1 ASCII 16 (slot 2 MegaRAM 2MB/2MB)  /N no reboot",13,10
         db "Collections: /L list, /G:n load game n,",13,10
         db " /C all (its menu); /CK /CY any ROM",13,10
         db " in KUC / Yamanooto mode",13,10,'$'

m_scc:   db "Konami SCC, slot 1",13,10,'$'
m_asc8:  db "ASCII 8 kB, slot 2",13,10,'$'
m_asc16: db "ASCII 16 kB, slot 2",13,10,'$'
m_ferr:  db "File error.",13,10,'$'
m_kon:   db "Konami (no SCC), slot 1",13,10,'$'
m_nokon: db "This core has no Konami mode in slot 1: use ROMLOAD.",13,10,'$'
m_notcoll: db "Not a known collection.",13,10,'$'
m_kucl:  db "Whole collection, slot 1 KUC mode",13,10,'$'
m_onlykuc: db "/C: not a known collection.",13,10,'$'
m_yaml:  db "Whole collection, slot 1 Yamanooto mode",13,10,'$'
m_noyam: db "Slot 1 is not in Yamanooto mode. In the OSD set",13,10
         db " Slot1 = MegaSCC+ 2MB, Slot1 ROM type = Yamanooto 8MB",13,10
         db " (32 MB SDRAM, cores from 2026-10-12).",13,10,'$'
m_nokuc: db "Slot 1 is not in KUC mode. In the OSD set",13,10
         db " Slot1 = MegaSCC+ 2MB, Slot1 ROM type = KUC 8MB",13,10
         db " (32 MB SDRAM, cores from 2026-10-12).",13,10,'$'
m_badnum: db "No such game: see /L.",13,10,'$'
m_t8:    db "8K     $"
m_t16:   db "16K    $"
m_t32:   db "32K    $"
m_tk4:   db "Konami $"
m_tscc:  db "SCC    $"
m_tmeg:  db "Mega   $"
m_disk:  db "A disk in a ROM (DSK2ROM): it boots with Nextor off.",13,10,'$'
m_keyn:  db "Hold N while resetting, or Nextor boots and not the ROM disk.",13,10,'$'
m_nbk:   db "NEXTOR_BOOT_KEYS",0,0,0,80h,0,0   ; A100h: one-time boot key N
m_nbk_e:
m_dsk2rom: db "DSK2ROM"
m_unknown: db "Mapper not found: give /K, /A or /1.",13,10,'$'
m_noslot: db "The cartridge RAM is not in that mode. In the OSD set$"
m_need1:  db 13,10," Slot1 = MegaSCC+ 2MB",13,10,'$'
m_need8:  db 13,10," Slot2 = MegaRAM 1MB/1MB (on cores before 2026-10-11:",13,10
          db " the option named MegaSCC+ 2MB)",13,10,'$'
m_need16: db 13,10," Slot2 = MegaRAM 2MB/2MB",13,10,'$'
m_toobig: db 13,10,"ROM too big for this mapper.",13,10,'$'
m_clr1:  db "Slot 1 ROM disabled.",13,10,'$'
m_loaded: db "Loaded.",13,10,'$'
m_boot:  db "Loaded, rebooting.",13,10,'$'
m_crlf:  db 13,10,'$'
fname:  ds 64
opt:    ds 16
