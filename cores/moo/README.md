# JTMOO — Wild West C.O.W.-Boys of Moo Mesa

By Jose Tejada (@topapate)

You can show your appreciation through
* [Patreon](https://patreon.com/jotego)
* [Paypal](https://paypal.me/topapate)
* [Github](https://github.com/sponsors/jotego)

An FPGA implementation of Konami's Moo Mesa arcade board, integrated into
[jtcores](https://github.com/jotego/jtcores) through JTFRAME. The MiSTer target
is the DE10-Nano with SDRAM. MiST and SiDi builds are explicitly skipped
because of the BRAM budget; other targets require their own verification.

The [core completion plan](doc/plan.md) is the primary work queue, with current
RTL findings, detailed verification steps and MiSTer acceptance gates.

The [detailed core audit](doc/audit.md) records known video, scene-capture and
verification issues. This checkout includes a provisional core-local K054539
model. It is not a verified release or the shared `jt539` implementation.

## Features in the OSD

- Four-player cabinet input wiring, with three action buttons per player.
- Service/test access through F2 (`JTFRAME_OSD_TEST`).
- EEPROM-backed game settings and stereo sound.
- JTFRAME pause and debug/layer controls; the current debug-status output
  exposes sound only, as described in the audit.

The game uses a small EEPROM instead of physical DIP switches for its settings.
Access configuration with F2, or button 1 plus coin on Analogue Pocket, and
follow the game menu. A valid default EEPROM is required for normal boot.

## PCB Accuracy

The following source material documents the original board. Its presence does
not establish that every corresponding RTL behavior has passed hardware tests.

| Area | Board evidence in this core |
|---|---|
| Main address decoder | Decoded [055373 PAL fusemap](pal/moomesa/055373.txt) |
| Sound address decoder | Decoded [054744 PAL fusemap](pal/moomesa/054744.txt) |
| Board interconnect and devices | [Moo Mesa schematic project](sch/moomesa/moomesa.kicad_sch), including [main](sch/moomesa/main.kicad_sch), [scroll](sch/moomesa/scroll.kicad_sch), [objects](sch/moomesa/objects.kicad_sch) and [sound](sch/moomesa/sound.kicad_sch) sheets |

## Supported games

The driver/configuration selects these original-board variants. Per-set
release validation remains a separate gate.

| Set | Version |
|---|---|
| `moomesa` | EAB |
| `moomesauac` | UAC |
| `moomesauab` | UAB |
| `moomesaaab` | AAB |

Bucky O'Hare and bootlegs are excluded in `cfg/mame2mra.toml`.

## **Hardware emulated**

Clocks below are configured rates, not new hardware measurements.

| Chip or subsystem | Clock/interface | Implementation/reference |
|---|---|---|
| MC68000 | 16 MHz nominal; DTACK and DMA arbitration | `jtmoo_main`, JTFRAME `jtframe_m68k`, fx68k |
| K053990 protection/block operation | 16 MHz enable, 16-bit bus master | `jtmoo_prot`; local `doc/moo.cpp` functional reference |
| Z80 | 8 MHz nominal, ROM/PCM backpressure | `jtmoo_sound`, JTFRAME/T80 |
| YM2151 | 4 MHz nominal; digital AUX audio | JT51 through `jtmoo_sound` |
| K054539 | 18.432 MHz enable, PCM ROM and reverb RAM | Provisional `jtmoo_k054539`; MAME and SiliconRE references in its header |
| K054321 | Main/sound mailbox and IRQ | Shared Riders implementation |
| K053252 | Programmable raster; 8 MHz pixel enable | Shared Run and Gun implementation |
| K054156/K054157 tile hardware | Four packed 4-bit tile streams | `jtmoo_scroll`, shared `jt05415x`, JTFRAME tilemaps |
| K053246 object hardware | 16-bit CPU/DMA interface, 32-bit ROM stream | Shared Simpsons object modules |
| K053251/K054338 and palette | Priority, foreground, RGB, shadow/brightness/blend | `jtmoo_colmix`, shared K053251, local `jt054338` |
| Serial EEPROM | 128-byte persistent store | `jt5911` and generated JTFRAME memory wrapper |

## Credits

- Jose Tejada and the [jtcores/JTFRAME](https://github.com/jotego/jtcores) contributors,
  including the Riders, Simpsons and Run and Gun core implementations.
- Rafael Eduardo Paiva Feener, credited in the core RTL headers.
- meathax, credited in the local K054539 implementation.
- Jorge Cwik: [fx68k](https://github.com/ijor/fx68k)
- Daniel Wallner, Sorgelig and the T80 contributors
- Jose Tejada: [JT51](https://github.com/jotego/jt51)
- Furrtek: [SiliconRE](https://github.com/furrtek/SiliconRE) custom chip research
- Caius: 054744 PAL dump
- R. Belmont, Acho A. Tang and the [MAME](https://github.com/mamedev/mame)
  contributors; retained source notices identify the imported files' authors.
- OpenAI Codex assisted with the documented audit, shell-wrapper cleanup and
  diagnostic tests. This does not imply upstream maintainer approval.

## License

Core RTL is GPL-3.0-or-later as stated in its source headers. Retain all original
copyright and license notices. Imported reference source and shared dependencies
retain their own notices and license terms; the GPL core license does not replace
those notices. ROM images are not included.

## How to install

Use an accepted release RBF and its matching MRA files. Place the RBF in
`/media/fat/_Arcade/` and the MRAs in the same `_Arcade` folder, or the equivalent
MiSTer release folders. Obtain the required ROM archives separately.

For automatic installation of available meatcores releases, add this entry to
`downloader.ini`, then run **Update All**:

```ini
[meathax/meatcores]
db_url = https://raw.githubusercontent.com/meathax/meatcores/db/db.json.zip
```

This entry downloads published releases; it does not certify or install this
working tree as a release.

## Development layout and checks

Keep configuration in `cfg/`, core-owned RTL in `hdl/`, checks in `ver/`, and
reference material in `doc/`, `pal/` and `sch/`. Reuse shared JTFRAME/device
modules through `cfg/files.yaml`; do not copy them into Moo for cosmetic changes.

The [audit](doc/audit.md) includes the neighbor-core comparison, per-subsystem
review, failing video counterexamples and remaining acceptance gates. Shell
wrapper tests use fake tools and require no ROMs:

```sh
python ver/audit/test_scripts.py --bash /path/to/bash -v
```

The [correction ledger](doc/fix-ledger.md) records the background-channel and
inactive-CPU fixes, focused regressions, production synthesis results and
remaining blockers. These results are not release or PCB-accuracy acceptance.
