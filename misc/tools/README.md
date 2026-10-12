# ZEMMIX utilities (MSX-DOS 2 / Nextor)

Small `.COM` tools for the users of ZEMMIX.  They are in `\UTILS` of the
ZEMMIX disk image; the sources assemble with
[pasmo](https://pasmo.speccy.org/) (`pasmo MEGALOAD.ASM MEGALOAD.COM`).

| Tool | What it does |
|---|---|
| [`MEGALOAD`](#megaload) | Loads a MegaROM into the cartridge RAM of ZEMMIX as it is, and starts it |
| [`DSK2DIR`](#dsk2dir) | Extracts the disk inside a disk-in-ROM (DSK2ROM) to a directory |
| [`SNDOFF`](#sndoff) | Silences the sound chips one by one (to find a stuck note) |
| [`SCCCMP`](#scccmp) | Compares the ROM loaded in the MegaSCC+ of slot 1 with its file |

## MEGALOAD

```
MEGALOAD file.ROM [/K | /4 | /A | /1] [/N]
MEGALOAD collection.ROM /L
MEGALOAD collection.ROM /G:n [/N]
MEGALOAD collection.ROM /C [/N]
MEGALOAD file.ROM /CK | /CY [/N]
```

Loads a MegaROM into the cartridge RAM of ZEMMIX **without changing a
byte** and reboots, so the ROM starts as a cartridge would.

| Mapper | Option | Where | OSD |
|---|---|---|---|
| Konami SCC | `/K` | slot 1, up to 2 MB | Slot1 = MegaSCC+ 2MB |
| Konami (no SCC) | `/4` | slot 1, up to 2 MB | Slot1 = MegaSCC+ 2MB |
| ASCII 8 kB | `/A` | slot 2, up to 1 MB | Slot2 = MegaRAM 1MB/1MB |
| ASCII 16 kB | `/1` | slot 2, up to 2 MB | Slot2 = MegaRAM 2MB/2MB |

* Without an option the mapper is guessed from the writes of the ROM to the
  bank registers (as openMSX does).
* Konami without SCC (Nemesis, Metal Gear, Usas...) runs in the Konami mode
  of the MegaSCC+ of slot 1 (bit 5 of its 7FFEh register, kept through a
  reset; cores from 2026-10-11).  On an older core MEGALOAD says so: use
  `ROMLOAD` there.
* Before loading, the slot is checked (two banks written and read back);
  if it is not in the mode needed MEGALOAD says which OSD setting to use.
* When it loads into slot 2, a ROM left in the MegaSCC+ of slot 1 would
  boot first: its header is cleared (only if slot 1 is RAM, never a real
  cartridge).
* A disk-in-ROM (DSK2ROM) is loaded too.  As the Nextor of ZEMMIX would
  boot instead of the disk of the ROM, MEGALOAD sets the Nextor one-time
  boot key `N` (Nextor off for that boot only) before rebooting.
* `/N` loads and goes back to DOS (for a disk-in-ROM: hold `N` while
  resetting).

Collections: `/L` lists the games of a collection, `/G:n` loads game `n`
alone (only its part of the file is read) with its mapper, as the menu of
the cartridge would start it.  Known:

* Konami Neo-Ultimate Collection (SMX Team, 8 MB, Yamanooto cartridge): 83
  games; its table gives 16 kB / 32 kB / Konami / Konami SCC.
* Konami Ultimate Collection (Manuel Pazos), 2014 (66 games) and Enhanced
  Edition 1.6 (96 games): found through the code of its launcher (sizes and
  order tables, names).  Its launcher runs every MegaROM in its own Konami
  mode, so `/L` says `Mega` and `/G` picks Konami or Konami SCC from the
  code of that game (as without an option).

A 16 kB game is mirrored at 8000h, an 8 kB one at 6000h / 8000h / A000h
too.  `MEGALOAD KNUC.ROM /L > LIST.TXT` keeps the list in a file.

Whole collection (`/C`; faster from the OSD: *Load ROM (max 8MB)*): the file into the 8 MB of slot 1 in the mode of
its cartridge, then a reboot into the menu of the cartridge (RC
combinations, 50/60 Hz, volumes...).  OSD: Slot1 = MegaSCC+ 2MB and *Slot1
ROM type* = `KUC 8MB` (Konami Ultimate Collection) or `Yamanooto 8MB`
(Neo-Ultimate); 32 MB of SDRAM (SDRAM 16-24 MB).  MEGALOAD checks that the
mode is the right one.  `/CK` / `/CY` load any ROM in the KUC / Yamanooto
mode, without looking for a menu (Pampas & Selene, emulator version: `/CK`).  The cartridge is emulated as openMSX does it:

* KUC: offset 7FFEh, mapper 7FFFh (A21-A20, Konami / Konami SCC, register
  and switching lock), SCC / SCC+, the DAC (Majutsushi, Synthesizer).
* Yamanooto: ENAR / OFFR / CFGR, 10-bit banks, Konami 4, SCC / SCC+, its
  PSG on ports 10h-11h (the second PSG of the core).
* Flash: the AMD commands for the saves of games (Pampas & Selene): program,
  sector erase (8 kB in the first 64 kB, else 64 kB).  One erased sector is
  tracked at a time; the saves live in the SDRAM until the core is loaded
  again (not written back to the file yet).

Why not `ROMLOAD`: it converts what it takes for Konami (no SCC) bank
writes to the SCC mapper **in any ROM**, and this breaks some games
(Ghosts'n Goblins for the GFX9000: its second screen was garbage because of
two changed bytes).  It also only knows slot 1.

## DSK2DIR

```
DSK2DIR file.ROM [directory]
```

Many MegaROMs are disks converted with DSK2ROM (by joyrex): a disk driver
plus the image of the disk.  DSK2DIR writes every file of that disk, with
its subdirectories, into a directory (by default one named after the ROM,
`LIFEMARS.ROM` -> `LIFEMARS`, created in the current directory).  The game
then runs from there (`BASIC AUTOEXEC.BAS`, `AUTOEXEC.BAT`...), without
the mapper or the disk driver of the ROM.

* Plain images: the FAT12 boot sector is looked for in the first 256 KB.
* Compressed images (DSK2ROM 0.80 with compression): sector table at 4000h
  and BitBuster packed sectors, unpacked with the depacker of the DSK2ROM
  driver.

## SNDOFF

```
SNDOFF
```

Silences the sound chips one at a time and waits for a key after each:
PSG, OPLL (MSX-MUSIC), OPL3 (MoonSound FM), OPL4 wave (MoonSound PCM), PCM
of the turbo R.  The step where a stuck note stops names the chip.  The
MoonSound must be on in the OSD (it switches its ports off, not its sound).

## SCCCMP

```
SCCCMP file.ROM
```

After `MEGALOAD file.ROM /N` (or `ROMLOAD file.ROM` without `/S`), compares
every 8 kB bank in the MegaSCC+ of slot 1 with the file and lists the banks
that differ, with the first different byte.  It showed that ROMLOAD
changes bytes of the ROMs it loads.
