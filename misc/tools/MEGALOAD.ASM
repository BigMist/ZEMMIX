; MEGALOAD.COM: loads a MegaROM as it is into the ZEMMIX cartridge RAM of
; slot 1 / slot 2 and reboots, MSX-DOS 2 / Nextor.
; Assemble: pasmo MEGALOAD.ASM MEGALOAD.COM
;
; Usage: MEGALOAD file.ROM [/K | /A | /1] [/N]
;   /K  Konami SCC: MegaSCC+ of slot 1 (OSD Slot1 MegaSCC+ 2MB), up to 2 MB
;   /A  ASCII 8 kB: slot 2 (OSD Slot2 MegaRAM 1MB/1MB), up to 1 MB
;   /1  ASCII 16 kB: slot 2 (OSD Slot2 MegaRAM 2MB/2MB), up to 2 MB
;   /N  load only, back to DOS
; Without /K /A /1 the mapper is guessed from the LD (nnnn),A of the ROM
; to the bank registers (as openMSX does).  Konami without SCC (bank
; registers 6000h / 8000h / A000h) is not supported: the ROM would have to
; be changed (ROMLOAD does it).  MEGALOAD never changes the ROM.
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
        jr z,opend
        ld a,(opt+1)
        and 0DFh
        cp 'N'
        jr nz,op0
        ld a,1
        ld (noboot),a
        jr opts
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
        jr opts
opend:  ld de,fname
        xor a
        ld c,43h                ; _OPEN
        call BDOS
        or a
        jp nz,ferr
        ld a,b
        ld (handle),a
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
        ld a,(rtype)
        cp T_KON
        jp z,konami
        or a
        jp z,unknown

        ld a,(rtype)            ; slot and size limit
        ld de,m_scc
        ld b,01h
        ld c,0                  ; 256 blocks of 8 kB
        cp T_SCC
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
        jr z,prok
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
blk:    ld a,(handle)           ; next 8 kB
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
        ld a,(rtype)
        cp T_SCC
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
        ld a,(rtype)
        cp T_SCC
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
gs_blk: ld a,(handle)
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
        ld hl,(c_scc)           ; scores
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
        ld a,(rtype)
        cp T_SCC
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
        ld a,(rtype)
        cp T_SCC
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
konami: ld de,m_konami
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
m_usage: db "Usage: MEGALOAD file.ROM [/K|/A|/1] [/N]",13,10
         db " /K Konami SCC (slot 1)  /A ASCII 8 (slot 2 MegaRAM 1MB/1MB)",13,10
         db " /1 ASCII 16 (slot 2 MegaRAM 2MB/2MB)  /N no reboot",13,10,'$'

m_scc:   db "Konami SCC, slot 1",13,10,'$'
m_asc8:  db "ASCII 8 kB, slot 2",13,10,'$'
m_asc16: db "ASCII 16 kB, slot 2",13,10,'$'
m_ferr:  db "File error.",13,10,'$'
m_konami: db "Konami without SCC: use ROMLOAD.",13,10,'$'
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
