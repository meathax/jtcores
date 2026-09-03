# Moo Mesa (Konami GX151 / PWB353126)

MiSTer FPGA port of Konami's *Moo Mesa* / *Bucky O'Hare* hardware (68000 +
Z80, 054156/054157 tilemaps, 053246/053247 sprites, 053251 + 054338 colour
mixing, YM2151 + K054539 sound). This document describes the chip-to-module
mapping and the deliberate deviations from the real board that this port
carries. Evidence classes follow the project convention: **KNOWN** (schematic
capture, silicon RE trace, or a decisive MAME cross-check), **INFERRED**
(derived from KNOWN evidence plus reasoning, not directly captured), and
**HYPOTHESIS** (plausible but not yet verified against hardware or a
directed test).

## 1. PCB chip to RTL module map

| PCB ref | Chip | RTL | Source | Evidence basis | State |
|---|---|---|---|---|---|
| N3 | MC68000 16 MHz | `jtframe_m68k` (fx68k) | jtframe | mature | complete |
| P6 | 055373 PAL20L10 main decoder | inline `casez` in `jtmoo_main.v` | local | `doc/055373` equations, cross-checked against MAME `moo_map` | complete |
| N4 | 053990 protection / DMA bus master | `jtriders_tmnt2` + generated MMR | riders | MAME `moo_prot_w`; SiliconRE `053990` folder | functional; byte-wide DMA (`bus_dsn` forced word-only) unverified, no Moo evidence it's exercised |
| L4 | 053252 CRTC 8 MHz | `jtk053252` + generated MMR | rungun | schematic; SiliconRE folder exists | functional, timing unverified |
| G4 / J1 | 054156 / 054157 tilemaps | `jt05415x.v`, `jt054157.v` (4x `jtframe_tilemap`) | modules/jt05415x | Furrtek 054156/054157 schematics + MAME register trace | layer association and register file wired; VRAM wait states and screen flip simplified (see deviations) |
| F10 / J10,K10 | 053246 / 053247 sprites | `jtsimson_obj` + `jt053246*` | simson | shared by simson/xmen/rungun | functional; sprite X/Y offset calibration against a known MAME frame still open |
| M9 | 053251 priority | `jtcolmix_053251` | simson | silicon-traced register map | complete |
| J3 | 054338 mixer / alpha / shadow / brightness | `jt054338.v` | local to moo | register shell matches MAME; SiliconRE folder exists | blend mode 0/1 (mix code 1) implemented; brightness stage implemented but HYPOTHESIS; mix codes 2-3 not implemented (Bucky O'Hare only, see deviations) |
| G4,H4,J4 | 3x HM6116 palette RAM | 3x `jtframe_dual_ram` in `jtmoo_colmix.v` | jtframe | schematic | complete |
| R6,R5 | 2x HM62256 work RAM | SDRAM `ram` bus | mem.yaml | schematic | complete |
| E9,F9 | 2x LH5168 object RAM (16 KB) | inside `jt053246_dma` path | simson | schematic: EA1-5 = A1-A5, EN0-7 = A8-A15, stride 0x100 | complete, mapping and DMA stride confirmed |
| L10,M10,N10 | 3x MB8464 VRAM | 3x `jtframe_dual_nvram` in `jt05415x.v` | jtframe | schematic | complete |
| C14 | Z80 8 MHz | `jtframe_sysz80` | jtframe | mature | complete |
| E7 | 054744 PAL16L8 sound decoder | inline `always` in `jtmoo_sound.v` | local | pins from schematic, ranges from MAME | complete |
| D13 | YM2151 4 MHz | `jt51` | jt51 | mature | complete; output routed as its own mixer channel, not through the K054539 (see deviations) |
| E4 | 054539 PCM 18.432 MHz | `jt054539` | modules/jt054539 | port of the jlrh/konami-fpga `k054539.v` (GPL-3.0), a behavioural model -- not the Furrtek gate-level netlist | ported and lint-clean; no AUX input and no second-ROM-bank (ROBS) select (see deviations); dynamically unverified against MAME/hardware audio |
| 3B1 / U,U2 | 054986A hybrid: 2x 054321 latches, AD1868 DAC, LA4705 | `jt054321` | riders | no RE citation | complete for the PCM digital attenuation path; FM bypasses this chip entirely (see deviations) |
| G3 | 051550 | none | none | MAME: EMI filter for coin counters; also identified as the watchdog kick source at control-latch bit 10 | coin-counter role correctly absent (cosmetic on MiSTer); watchdog kick unimplemented (see deviations) |
| N2 / B13 | ER5911 EEPROM | `jt5911` | jteeprom | mature | complete |
| Q4 | 74LS174/175 control latch (0x0DE000) | in `jtmoo_main.v` | local | schematic | complete |
| Q3 | 74LS148 IPL encoder | in `jtmoo_main.v` | local | schematic | levels verified except the level-4/bit-11 gating question (kept ungated, matches capture) and `blnk_sel`'s downstream net (unresolved, parked) |
| -- | 054000 collision (Bucky O'Hare only) | `jtk054000` + MMR | simson | mature | complete |

## 2. Deliberate deviations from real hardware

These are intentional, documented gaps between this port and the real board
-- not bugs to silently "fix" without new evidence.

1. **Watchdog (control latch bit 10, 051550 kick) is unimplemented.** The
   real board's control latch bit 10 kicks a 051550-based watchdog; the
   schematic capture gives no timeout value to reproduce, so this port never
   times out. See the control-latch decode comments in `jtmoo_main.v`. Not
   implemented by design.

2. **VRAM DTACK wait states use the framework default.** `vram_cs` (and
   `scr_cs`) stay at jtframe's normal one-wait-state DTACK cycle rather than
   a hardware-matched multi-cycle chain, because the `~M6`/`M3` clock
   frequencies that would drive the real wait-state generator are undriven
   in the schematic capture. HYPOTHESIS pending those frequencies; see the
   D9 comment block in `jtmoo_main.v`.

3. **054338 mix codes 2-3 (MIX1) are not implemented.** Only blend code 1
   (interpolation/additive, mode 0/1) is wired up; codes 2 and 3 are used by
   Bucky O'Hare only and are out of scope for Moo Mesa. See
   `jtmoo_colmix.v`'s `mix_blend`/`mix_sel` comments.

4. **Brightness datapath is implemented but HYPOTHESIS.** The digital
   `apply_bright` stage (`(x*bri1_lvl)>>8` per channel) is wired, but the
   real board applies brightness in the analogue domain after the DAC over
   an uncaptured reference path, and Moo Mesa's ROM never writes a non-zero
   brightness register in the traced attract-mode run -- this stage is only
   checked by a directed testbench forcing the register, not by a MAME
   frame diff.

5. **Four service inputs are collapsed to one.** The board has four
   independent service-coin inputs; jtframe/MiSTer expose only a single
   service line, so all four are tied to that one bit (`{4{service}}`).
   Framework limitation, not board behaviour. See `jtmoo_main.v` and
   `jtmoo_game.v`.

6. **FM is routed as a separate audio channel, bypassing the K054539's
   internal AUX summing.** On the real board the YM2151's serial output
   feeds the K054539's AUX1 pin, the chip sums FM with PCM internally, and
   the K054321 attenuates the combined signal. The ported K054539 module has
   no AUX input; the upstream author found that summing FM into the
   accumulator railed it and split FM out into its own `fm_l`/`fm_r` mixer
   channel instead. Net effect: the main CPU's K054321 volume writes
   attenuate PCM but not FM. INFERRED from the port's own comments and the
   054986A hybrid's role in the chip-to-module table above.

7. **Bucky O'Hare's second PCM ROM bank (ROBS) is unsupported.** The real
   K054539 selects a second sample ROM via its ROBS pin (Bucky O'Hare only,
   not used by Moo Mesa); the ported behavioural module has no
   ROBS-equivalent select at all. See `jtmoo_sound.v`.
