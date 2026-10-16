# ZEMMIX

An MSX core for the MiST family boards (SiDi128, Poseidon GX150, NeptUNO+):
an MSX2+ and MSX turbo R machine that also runs MSX1 and MSX2 software (it is
not an MSX1, but keeps its backward compatibility).  It is built on the
OCM-PLD firmware of the 1chipMSX / Zemmix Neo (v3.9.2+, by KdL and others)
and extended with what a turbo R and its usual expansions have: the R800,
the S1990, the turbo R PCM, the MoonSound (OPL4) and the GFX9000 (V9990).

## Boards

| Board | FPGA | Cartridge slot | 2nd SDRAM | HDMI | V9990 | Project |
|---|---|---|---|---|---|---|
| SiDi128 | Cyclone 10 LP 10CL120 | no | yes | yes | yes | `SiDi128/` |
| Poseidon GX150 | Cyclone IV GX150 | yes | no | no | no | `poseidon-gx150/` |
| NeptUNO+ | Cyclone IV GX150 | yes | no | no | no | `NeptUNOplus/` |
| NeptUNO+ dual SDRAM | Cyclone IV GX150 | no (its pins go to the 2nd SDRAM) | yes | no | yes | `NeptUNOplus_dual/` |

## From OCM-PLD

The base machine is `emsx_top` of OCM-PLD (`ocm-pld-dev/`, submodule),
kept as close to upstream as possible.

### System
* Z80 (T80) at 3.58 MHz, with the OCM turbo speeds (OSD *CPU Clock* and
  smart commands).
* The BIOS (`OCM-BIOS.DAT`) comes from the firmware as `ZEMMIX.ROM` when the
  core starts, or from the OSD (*Load BIOS*), into the ESE-RAM with the MSX in
  reset; it is then write protected and stays over every reset.  Without
  it, the IPL ROM loads `OCM-BIOS.DAT` from the disk image as on the OCM.
* Switched I/O ports: the OCM smart commands (`SETSMART`) for speed,
  slots, volumes, keyboard layout...
* System timer (E6h / E7h) and the turbo R PCM (A4h / A5h) of OCM-PLD.
* RTC (clock and settings), Kanji ROM JIS1 / JIS2.

### Memory and storage
* Memory mapper of 2048 or 4096 KB (OSD *RAM*).
* MegaSD: the SD card as a disk for Nextor / MSX-DOS; here a VHD image
  mounted from the OSD (*Load virtual disk*, *internal MegaSD*).
* ESE-SCC (MegaSCC+ 2 MB, with its SCC / SCC+) in slot 1 or slot 2, and
  ESE-RAM (MegaRAM 1 MB or 2 MB, ASCII8 / ASCII16) in slot 2, to load ROM
  images from disk (OSD *Slot1* / *Slot2*).
* External cartridge slot on the Poseidon GX150 and the NeptUNO+.

### Sound
* PSG with key click (I/O A0h-A2h).
* SCC / SCC+ of the two ESE-SCC slots.
* MSX-MUSIC (OPLL, YM2413).
* turbo R PCM.
* Cassette input (OSD *Tape sound*).
* Per source volumes of the OCM (PSG, SCC, OPLL).

### Input and communication
* PS/2 keyboard (OCM layouts) and mouse, two joysticks, autofire.
* MIDI out (OCM MIDI interface).
* ESP8266 Wi-Fi with the UNAPI interface.

## Extras of ZEMMIX

### MSX turbo R
* **R800**: its own core (`R800/`, submodule
  [rampa069/R800](https://github.com/rampa069/R800)), derived from NextZ80,
  with the R800 timing of openMSX (speed regulator, MULUB / MULUW, page
  break waits).  zexall gives the same results as openMSX's R800, on the
  board too.  The Z80 stays a T80 (`T80/`, submodule).
* **S1990** registers (E4h / E5h): Z80, R800 ROM and R800 DRAM modes
  (`CHGCPU`).
* turbo R BIOS in `OCM-BIOS.DAT` of the disk image.

### Video
* **V9958 replaced by the V9968** of HRA! (`v9968/`), MSX2+ compatible.
* **V9990 / GFX9000** (ports 60h-6Fh) on the boards with a 2nd SDRAM: its
  own core (`v9990/`, submodule), all modes but B5 / B6, the command
  engine, sprites.  The 512 KB VRAM is in the 2nd SDRAM behind a line
  cache.
* OSD *HDMI screen*: Auto (the V9990 while its display is on), V9958 or
  V9990.  With HDMI, the chosen screen goes to HDMI and the other one to
  VGA.
* Scandoubler (VGA) or 15 kHz RGB, scanlines, HDMI on the SiDi128.

### Sound
* **PSG**: Kyp069's AY-3-891x instead of the OCM one, modified for ZEMMIX
  with a YM2149 personality (OSD *PSG*: YM2149 by default, or AY-3-8910;
  *PSG2* the same for the PSG of a Yamanooto).
* **MSX-MUSIC** with IKAOPLL (YM2413 from a die shot) instead of the OCM
  VM2413.
* **MoonSound**:
  * FM: OPL3 (`opl3_fpga` of Greg Taylor) on the 50 MHz clock, ports
    C4h-C7h.
  * Wave: OPL4 (YMF278B PCM engine of srg320) on ports 7Eh / 7Fh, 2 MB of
    wave RAM plus the YRW801 sample ROM, loaded from `ZEMMIX.R01` by the
    firmware.  The wave memory is in the 2nd SDRAM on the SiDi128 and in
    the top 4 MB of the main SDRAM elsewhere.
  * Can be turned off in the OSD.
* **Mixer** (`misc/audio_mix.sv`) for all the sources: PSG, SCC x2,
  MSX-MUSIC, MoonSound FM and wave, turbo R PCM and tape, with the OCM
  volumes.  Outputs: sigma-delta (jack), I2S, S/PDIF and HDMI audio on the
  SiDi128.

## OSD

Main menu: *Load virtual disk*, *Load BIOS*, *Load ROM (max 8MB)*, *Slot1
ROM type*, the sections *System*, *Video Options* and *Audio Options*,
*Reset* and *Eject cartridge & reset*.  The sections only group the options:
a saved configuration keeps its values, but *internal MegaSD* is a new
option, On by default.

| Option | Values |
|---|---|
| Load BIOS | an `OCM-BIOS.DAT` (`.DAT`) into the ESE-RAM, as `ZEMMIX.ROM` at start (MSX in reset, then it boots it) |
| Eject cartridge & reset | clears the ROM written into the MegaSCC+ / MegaRAM of slot 1 and 2 (and a collection) and resets: the MSX starts without it |
| Load ROM (max 8MB) | a collection ROM into the 8 MB of slot 1 (MSX in reset, seconds) |
| Slot1 ROM type | MegaSCC+, KUC 8MB, Yamanooto 8MB (collection cartridges, 32 MB SDRAM) |
| **System** | |
| CPU Clock | Standard, Turbo |
| RAM | 2048 KB, 4096 KB |
| Slot 1 | External (cartridge), MegaSCC+ 2 MB |
| Slot 2 | External, MegaSCC+ 2 MB, MegaRAM 1 MB/1 MB (ASCII 8), MegaRAM 2 MB/2 MB (ASCII 16) |
| Internal MegaSD | On (default), Off |
| **Video Options** | |
| Video Hz | Auto, 60 Hz (NTSC), 50 Hz (PAL) |
| Palette | V9968, openMSX |
| HDMI screen (V9990 builds) | Auto, V9958, V9990 |
| Scanlines | Off, 25 %, 50 %, 75 % |
| **Audio Options** | |
| MoonSound (OPL3 / OPL4) | On, Off (its ports; the sound stays mixed) |
| PSG | YM2149, AY-3-8910 (32 or 16 step envelope, register read back) |
| PSG2 (Yamanooto) | YM2149, AY-3-8910 |
| Tape sound | Off, On |

### Collection cartridges

Konami Ultimate Collection (Manuel Pazos) and Konami Neo-Ultimate
Collection (SMX Team, Yamanooto cartridge) run as the real cartridges, with
their menus: set *Slot1* = MegaSCC+ 2MB and *Slot1 ROM type* = KUC 8MB or
Yamanooto 8MB, then *Load ROM (max 8MB)* and pick the `.ROM` (up to 8 MB, at
SDRAM 16-24 MB): the MSX restarts into the menu.  The mappers follow openMSX
(KUC: offset, A21-A20, Konami / SCC, DAC; Yamanooto: 10-bit banks, Konami 4,
its PSG on 10h-11h) and the flash takes the saves of games (Pampas &
Selene) until the core is loaded again.  `MEGALOAD /C` does the same from
MSX-DOS, `MEGALOAD /L` and `/G:n` load one game of a collection
([misc/tools](misc/tools/README.md#megaload)).

## SD card

* The core (`ZEMMIX_<board>_3.9.2+.rbf`).
* `ZEMMIX.ROM`: the turbo R BIOS (`OCM-BIOS.DAT` renamed), loaded at start.
* `ZEMMIX.R01`: the YRW801 MoonSound ROM, loaded at start.
* A VHD image with Nextor 3.0, `OCM-BIOS.DAT` (turbo R BIOS, used when there
  is no `ZEMMIX.ROM`) and the tools, mounted with *Load virtual disk*.

The firmware sends `ZEMMIX.ROM` and `ZEMMIX.R01` from the core's folder (or
the root) through data_io, index 0 and 1.  Before this version
`ZEMMIX.ROM` was the YRW801: rename it to `ZEMMIX.R01`.

The image has turbo R and GFX9000 software, MoonSound music (RoboPlay) and
test tools: `ZEXDOC` / `ZEXALL` (`ZEXR800.BAT`), `R800BEN`, `SNDTEST.BAS`,
`OPL4MEM.BAS`, `OPL4SIN.BAS`, `V99TEST.COM`.

## Utilities

MSX-DOS 2 tools made for ZEMMIX, in `\UTILS` of the disk image (sources in
[`misc/tools`](misc/tools/README.md)):

* **MEGALOAD**: loads a MegaROM (Konami SCC, ASCII 8, ASCII 16) into the
  cartridge RAM of slot 1 / slot 2 **without changing it** and starts it;
  disk-in-ROM cartridges (DSK2ROM) boot their own disk.  Use it instead of
  ROMLOAD, which patches the ROMs it loads.
* **DSK2DIR**: extracts the disk inside a disk-in-ROM (DSK2ROM, plain or
  compressed) to a directory, to run the game from the SD card.
* **SNDOFF**, **SCCCMP**: diagnostics (stuck notes, loaded ROM contents).

Test tools for the VDP and the V9990 are in
[`misc/v9968/tools`](misc/v9968/tools/README.md) and
[`misc/v9990/tools`](misc/v9990/tools/README.md).

## Building

Quartus Prime Lite 21.1, one project per board directory:

```bash
git clone --recursive git@github.com:BigMist/ZEMMIX.git
cd ZEMMIX/SiDi128
quartus_sh --flow compile ZEMMIX_SiDi128
```

Submodules: `ocm-pld-dev`, `R800`, `T80`, `v9990`, `IKAOPLL`,
`mist-modules`.

## Credits and thanks

ZEMMIX is put together from the work of many people.  Thanks to all of them:

| Part | Authors | Source |
|---|---|---|
| OCM-PLD (the MSX2+ machine, `emsx_top`) | KdL (Luca Chiodi), on the ESE MSX-SYSTEM3 of Kazuhiro Tsujikawa (ESE Artists' factory); other contributors in its `history.txt` | [gnogni/ocm-pld-dev](https://github.com/gnogni/ocm-pld-dev) |
| V9968 VDP | HRA! (t.hara) | [hra1129/V9968_Cartridge](https://github.com/hra1129/V9968_Cartridge) |
| R800 (derived from NextZ80) | Nicolae Dumitrache (NextZ80) | [rampa069/R800](https://github.com/rampa069/R800), [NextZ80 at OpenCores](https://opencores.org/projects/nextz80) |
| T80 (the Z80) | Daniel Wallner and the T80 contributors | [rampa069/T80](https://github.com/rampa069/T80) |
| V9990 (GFX9000) | Ramón Martínez | [rampa069/v9990](https://github.com/rampa069/v9990) |
| OPL3 (MoonSound FM) | Greg Taylor, after Nuked-OPL3 of nukeykt | [gtaylormb/opl3_fpga](https://github.com/gtaylormb/opl3_fpga), [nukeykt/Nuked-OPL3](https://github.com/nukeykt/Nuked-OPL3) |
| OPL4 PCM engine (YMF278B) | Sergiy Dvodnenko (srg320), from MAME's ymf278b (R. Belmont, Olivier Galibert, hap) | [srg320/Arcade-PsikyoSH2_MiSTer](https://github.com/srg320/Arcade-PsikyoSH2_MiSTer) |
| IKAOPLL (MSX-MUSIC) | Raki (ika-musume) | [ika-musume/IKAOPLL](https://github.com/ika-musume/IKAOPLL) |
| AY-3-891x / YM2149 PSG | Kyp069, modified for ZEMMIX (YM2149 personality) | [Kyp069/AY-3-891x](https://github.com/Kyp069/AY-3-891x) |
| MiST modules (user_io, OSD, scandoubler, data_io) | Till Harbaum, Sorgelig, Gyorgy Szombathelyi and the MiST community | [mist-devel/mist-modules](https://github.com/mist-devel/mist-modules) |
| NeptUNO+ dual SDRAM pinout | delgrom | [delgrom/NeoGeo_FPGA](https://github.com/delgrom/NeoGeo_FPGA) |
| Reference for the R800, the OPL4 and the V9990 | the openMSX team | [openMSX/openMSX](https://github.com/openMSX/openMSX) |
| Nextor | Konamiman | [Konamiman/Nextor](https://github.com/Konamiman/Nextor) |
| RoboPlay (MoonSound player) | RoboSoft Inc. (ToriHino) | [ToriHino/RoboPlay](https://github.com/ToriHino/RoboPlay) |
| SofaRun | Louthrax | [msx.org downloads](https://www.msx.org/downloads/sofarun) |

The licenses of each part are in their own files (OCM-PLD: custom license,
`ocm-pld-dev/LICENSE`; R800 / NextZ80: LGPL 2.1; OPL4 engine: BSD 3-clause,
`misc/opl4/NOTICE`; OPL3: LGPL; PSG: GPL 2).
