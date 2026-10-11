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
MEGALOAD file.ROM [/K | /A | /1] [/N]
```

Loads a MegaROM into the cartridge RAM of ZEMMIX **without changing a
byte** and reboots, so the ROM starts as a cartridge would.

| Mapper | Option | Where | OSD |
|---|---|---|---|
| Konami SCC | `/K` | slot 1, up to 2 MB | Slot1 = MegaSCC+ 2MB |
| ASCII 8 kB | `/A` | slot 2, up to 1 MB | Slot2 = MegaRAM 1MB/1MB |
| ASCII 16 kB | `/1` | slot 2, up to 2 MB | Slot2 = MegaRAM 2MB/2MB |

* Without an option the mapper is guessed from the writes of the ROM to the
  bank registers (as openMSX does).  Konami without SCC is refused: it can
  only run in an SCC cartridge after changing the ROM, use `ROMLOAD` for it.
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
