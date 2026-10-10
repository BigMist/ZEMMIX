; I/O and misc instructions; ports >= 10h are logged by tbio.cpp, IN gives port ^ 5Ah
        org 100h
        ld sp,0E000h
        ld a,12h
        out (34h),a             ; OUT 1234 12
        ld a,56h
        in a,(78h)              ; IN 5678 -> 22
        call pa
        ld bc,9ABCh
        ld d,0DEh
        out (c),d               ; OUT 9ABC DE
        in e,(c)                ; IN 9ABC -> E6
        ld a,e
        call pa
        db 0EDh,70h             ; IN F,(C) (flags only)
        ld bc,0320h
        ld hl,buf
        otir                    ; OUT 0220 11, 0120 22, 0020 33 (B decremented first)
        ld bc,0230h
        ld hl,buf+8
        inir                    ; IN 0230 6A, IN 0130 6A
        ld a,(buf+8)
        call pa
        ld a,(buf+9)
        call pa
        ld bc,0140h
        ld hl,buf
        outi                    ; OUT 0040 11
        ld bc,0150h
        ld hl,buf
        outd                    ; OUT 0050 11
        ld hl,1234h
        push hl
        ld hl,5678h
        ex (sp),hl
        call phl                ; 1234
        pop hl
        call phl                ; 5678
        ld ix,0ABCDh
        push ix
        ld ix,0
        ex (sp),ix
        push ix
        pop hl
        call phl                ; ABCD
        pop hl
        ld a,3Fh
        ld i,a
        ld a,0
        ld a,i
        call pa                 ; 3F
        im 2
        im 1
        ld hl,rstret
        ld (39h),hl
        ld a,0C3h
        ld (38h),a
        rst 38h                 ; -> rstret
        ld a,0EEh
        call pa
        jp done
rstret: ld a,38h
        call pa
        ret
done:   ld hl,retnt
        push hl
        retn
retnt:  ld hl,retit
        push hl
        reti
retit:  ld a,99h
        call pa
        out (2),a
phl:    ld a,h
        call hex
        ld a,l
        call hex
        ld a,' '
        out (1),a
        ret
pa:     call hex
        ld a,' '
        out (1),a
        ret
hex:    push af
        rrca
        rrca
        rrca
        rrca
        call nib
        pop af
nib:    and 0Fh
        add a,'0'
        cp '9'+1
        jr c,nib1
        add a,7
nib1:   out (1),a
        ret
buf:    db 11h,22h,33h,44h,55h,66h,77h,88h,0,0
