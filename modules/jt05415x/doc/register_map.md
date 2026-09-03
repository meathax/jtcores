# K054157 register file (0x0D8000-0x0D8007, `BNK~SCR`)

Written 2026-09-03 for Group 2 item B2 of `D:\evidence\moo\audit\remaining_plan.md`.
Covers the 14 fields `jt054157_mmr.v` decodes from `modules/jt05415x/cfg/mmr.yaml`
(the 054157's own 4-word CPU register window, separate from the 054156's
32-word window at 0x0C0000).

Evidence used, in order:

1. Furrtek SiliconRE `054157/README.md` (tier 1, die-level, applies to the
   physical chip regardless of board).
2. MAME register-write trace, Moo Mesa (moomesa), coin+start preset, 3600
   frames: `D:\evidence\moo\mame\k054157_regwrites_3600f.jsonl` (10083
   records). Extracted per-address value history with a throwaway script
   (`D:\vibes\...\scratchpad\analyze157.py` / `analyze157b.py`); not
   re-ingested verbatim per the project's trace-handling rule.
3. `modules/jt05415x/cfg/mmr.yaml` field descriptions (the names/guesses
   already present in the tree before this pass; kept where evidence agrees,
   corrected in comments where it does not).
4. `register_map_054156157_netlist_notes.md` (same directory) -- a second,
   independent tier-1 source for the same 4-word register window, derived
   from the `doc/054156/jt054156.v` netlist-conversion reference rather than
   the README. This file used to occupy this document's path (git history:
   commit `bf4a22c`, 2026-09-01); this B2 pass replaced it with the present,
   live-RTL-accurate content and moved the original to its own file rather
   than discard it, since it independently corroborates two findings below.

The board writes exactly four words (0x0D8000, 0x0D8002, 0x0D8004, 0x0D8006);
each word's low byte is the register the README documents as "00", "02",
"04", "06". The CPU always writes the same value into both bytes of a word on
this ROM (word = {byte,byte}), so only 8 bits of state exist per register.

## Register 0x00 (`mmr[0]`) -- steady value 0x08 -> 0x48 at frame 409 (PC 0x19D6)

| bit | field (yaml)  | README meaning                         | trace behaviour                          | evidence class |
|-----|---------------|------------------------------------------|-------------------------------------------|-----------------|
| 0   | `hofs_phase`  | "Number of layers 2/4, 0:2 1:4"          | always 0                                   | HYPOTHESIS (README's meaning conflicts with Moo Mesa using 4 active pipelines at bit=0; not wired, see below) |
| 3   | `clk_fanout`  | "?" (undocumented)                       | always 1                                   | HYPOTHESIS |
| 4   | `ram_clkph`   | "Enable full display horizontal flip" (reg shared with 054156) | always 0 | INFERRED -- matches `glob_ctrl[4]`=0 (054156's own H-flip bit, already wired to `flip` in `jt05415x.v:118`); this 054157-side copy looks redundant with that bit and is not separately consumed by the pixel pipeline, so it is left unwired |
| 6   | (none)        | not documented anywhere                  | 0 until frame 409 (PC 0x19D6), then 1 for the rest of the run | HYPOTHESIS -- observed but has no candidate function; not one of the 14 originally-decoded fields, so no port exists for it and none is added here (would be inventing a mux) |

Reg 0x00 bit 0 reading "number of layers" at value 0 is inconsistent with Moo
Mesa's RTL always running four independent tilemap pipelines; either the
polarity is inverted from the README's phrasing, or this bit governs an
internal fetch/clock mode unrelated to which of the four externally-visible
pipelines are populated (the RTL never gates layer count on any register).
Left as HYPOTHESIS and unwired -- do not invent the mux.

## Register 0x02 (`mmr[2]`) -- steady value 0xFF from frame 8 onward, never rewritten

| bit | field         | README meaning                    | trace value | action |
|-----|---------------|------------------------------------|-------------|--------|
| 0   | `a_hofs_flip` | "Enable tile X flips" (paired with HOFSA / layer F) | 1 | **wired** |
| 2   | `b_hofs_flip` | same, paired with HOFSB / layer A  | 1 | **wired** |
| 4   | `c_hofs_flip` | same, paired with HOFSC / layer B  | 1 | **wired** |
| 6   | `d_hofs_flip` | same, paired with HOFSD / layer C  | 1 | **wired** |

KNOWN from the README ("02[7:0]: Some bits shared with 054156; 0,2,4,6:
Enable tile X flips"), independently corroborated by
`register_map_054156157_netlist_notes.md`'s netlist-conversion-derived
reading of the same 4 bits ("Per-layer H offset flip enables for HOFSA,
HOFSB, HOFSC, and HOFSD") -- two different tier-1 sources agree. This
directly contradicts the plan's original working hypothesis (that these
bits select/negate the HOFSA..HOFSD constant offsets) -- there is no README
or netlist-reference support for an offset-sign or phase-select reading, and
the yaml's own pre-existing field description ("HOFSA flip enable") already
agreed with both tier-1 sources rather than the sign-select hypothesis.
Implemented as: `<layer>_hf <= tflip[0] & <x>_hofs_flip;` in
`jt05415x.v` (gates the per-tile horizontal-flip attribute bit, does not
touch the HOFSA..HOFSD position constants). Because the ROM holds all four
bits at 1 for the entire traced run (frame 8 through 3599, coin+start+3600f),
this is a no-op today -- it removes genuinely dead register-file code and is
INFERRED-safe (no way to observe the bit=0 case from this ROM alone; a
title that sets it to 0 would be needed to fully confirm the AND-gate
semantics rather than some other "enable" mechanism).

## Register 0x04 (`mmr[4]`) -- steady value 0x60 from frame 8 onward

| bit | field         | README meaning        | trace value | evidence class |
|-----|---------------|------------------------|-------------|-----------------|
| 3   | `ramout_mux`  | "?" (reg 04 bits 6:4 undocumented beyond "select 8/16bit mode?") | 0 | HYPOTHESIS |
| 4   | `dbout_mux`   | "                                                              " | 0 | HYPOTHESIS |
| 5   | `vc_dir`      | possibly the "select 8/16-bit mode" bit README mentions        | 1 | HYPOTHESIS |
| 6   | `crom_decode` | "                                                              " | 1 | HYPOTHESIS |

README: "04[7:0]: Some bits shared with 054156; [6:4]: ?; 3: Select 8/16bit
mode ?" -- itself marked uncertain by Furrtek. Constant for the whole run;
left in `unused_157` per the plan's rule 5 (fields the ROM never changes from
reset stay constants).

## Register 0x06 (`mmr[6]`) -- transient 0x00 at frames 405-407 (reset/init), settles to 0xD0 from frame ~408 onward, rewritten ~10000 times/run at the same constant value (multiple PCs inside the per-layer scroll-update routine: 0x24ca/0x2516/0x25f8)

| bit | field       | README meaning                                             | trace value | evidence class |
|-----|-------------|--------------------------------------------------------------|-------------|-----------------|
| 5   | `db_lane`   | "5: 1=8-bit ROM access, 0=16-bit"                             | 0 (16-bit)  | KNOWN (matches the board: T8/T10 065A08 ROMs are wired for 16-bit access, `scroll.md` GAP-free MATCH section) -- constant, left in `unused_157` |
| 6   | `col_src0`  | "[7:6]: Choice of bits in VRAM attribute for X/Y tile flip"  | 1           | INFERRED -- see B3 note below |
| 7   | `col_src1`  | same field, other bit                                        | 1           | INFERRED -- see B3 note below |

Despite the high write rate, the *value* never changes after the frame
405-407 reset transient -- the driver simply rewrites the same constant
every time it touches any of the four layers' scroll registers (a common
Konami idiom, not a per-frame toggle). Per the plan's rule 5, a
register whose value is observed constant stays in `unused_157`; the field
identities below are recorded for B3 but not wired.

### B3 note (col_src0/col_src1 vs. FPAL4/DFI8)

The README's reading of reg 0x06 bits 7:6 ("choice of bits in VRAM attribute
for X/Y tile flip") describes the *same kind of function* 054156 already
performs with its own `irq_attr[7:6]`/`fbits` field (`jt05415x.v` `assign
fbits = irq_attr[7:6]`), not a colour/palette-bit source selector. That
argues AGAINST col_src0/1 being the source of the FPAL4/DFI8 (5th palette
bit on layer "a") mux, independent of the fact that both bits are pinned at
`11` for the whole run and therefore cannot be observed toggling either way.
The Furrtek 054157 pinout (`054157_pinout.ods`, beeped from a Metamorphic
Force donor chip -- die-level, board-independent) does independently confirm
that the physical pin carrying DFI8 (die pin 137, documented there as pin
"137 | BCOL8 | K055555 67 | From ROM data or attribute") is a genuinely
muxed output at the die level, so *some* register bit does select it -- just
not, on the available evidence, col_src0/1.

Update after recovering `register_map_054156157_netlist_notes.md` (see
above): that netlist-conversion-derived source describes the SAME two bits
(reg 0x06 bits 6-7) as "color/attribute column source selection" -- a
noticeably more specific, more B3-relevant reading than the README's "choice
of bits in VRAM attribute for X/Y tile flip", and one that sits much closer
to being the actual DFI8-source mux. This raises rather than lowers B3's
priority for a follow-up pass (ideally reading `doc/054156/jt054156.v`'s
actual gate-level definition of `jt054157_page02_cpu_entry` bits `reg6_d6`/
`reg6_d7` directly, or finding a title that writes col_src0/1 to a non-`11`
value). It still does not change today's conclusion: the bits are constant
at `11` for the whole traced Moo Mesa run, so no A/B behavioural test is
possible from this ROM, and the plan's "do not invent a mux" rule applies
just as before. No RTL change made; current wiring (`tcolor[0]` ->
`a_pal[4]`, a third-party/konami-fpga measurement, see
`jtmoo_colmix.v:116-119`) stands, evidence class held at INFERRED (with a
somewhat stronger competing candidate now on record than before).

## Summary of fields left in `unused_157` (10 of 14)

`hofs_phase, clk_fanout, ram_clkph, ramout_mux, dbout_mux, vc_dir,
crom_decode, db_lane, col_src0, col_src1` -- every one of these is observed
constant for the entire traced 3600-frame coin+start run
(`k054157_regwrites_3600f.jsonl`), so there is no ROM-driven behaviour to
implement, and their exact functions are HYPOTHESIS (README marks most of
them "?" itself) or INFERRED-but-not-actionable (col_src0/1, db_lane). Per
the plan's rule ("if the ROM trace shows they never change, leave them in
unused_157 with a comment citing the trace file"), no further RTL change is
made for these 10 fields.

## Fields wired (4 of 14)

`a_hofs_flip, b_hofs_flip, c_hofs_flip, d_hofs_flip` -- wired as per-layer
tile-horizontal-flip enables in `jt05415x.v` (KNOWN function from the
Furrtek README; INFERRED-safe wiring since the ROM never exercises the 0
state).
