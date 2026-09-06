# Moo Mesa core audit — 2026-09-05

Follow-up implementation is recorded in [fix-ledger.md](fix-ledger.md).
AUD-03's isolated inactive-CPU branch and AUD-02's background byte packing
have now been corrected and focused-tested. Four-set MRA generation also
passes. The original findings and receipts below remain the pre-fix baseline;
they are not a claim that every blocker is still unchanged or now closed.

## Verdict

The core already has the appropriate **jtcores monorepo layout and module decomposition**. Keep `cfg/`, `hdl/`, `ver/`, `doc/`, `pal/`, and `sch/`; do not convert this core to a standalone Template_MiSTer tree. Its tile path already uses shared JTFRAME tilemap machinery behind a chip-specific wrapper.

**Not ready for a clean-code or release sign-off.** Two synthetic video tests reproduce functional defects, the scene-only build fails compilation, the inherited dump format loses state, and strict lint remains nonzero. The shell-wrapper cleanup is complete and tested. No synthesizable HDL, configuration, constraints, shared code, or bitstream changed.

This is a source-wide core audit and focused diagnostic exercise, not a claim of complete PCB accuracy, MAME equivalence, timing closure, or gameplay validation. Schematic files were inventoried and existing evidence references checked; this audit did not electrically re-derive every KiCad net or every chip equation.

## Identity, scope and evidence

- Repository snapshot: `8248dc6c3414dcd251be2778f80c82da78103acf`.
- Write boundary: `cores/moo` only. No upstream pull, commit or push.
- Pre-existing tracked edits: `cores/simson/hdl/jtsimson_obj.v` and `modules/jt05415x/hdl/jt05415x.v`. Both participate in Moo. Results refer to that dirty working tree, not solely to HEAD.
- Pre-existing untracked root files and `.mame_mcp/` were preserved; the locally present `modules/jtframe/src/jtframe/jtframe.exe` is also untracked.
- No root `.codegraph/` was present. Local source/manifests and bounded searches were used.
- Guidance: `jtcode`, its style/safe-change/submission references and practice database at upstream commit `4dcc97cdaea65dc8d1a9ea77bd4ce5b0b5992178`; the newer local neighbors take precedence for corpus comparisons.
- Shared lessons applied: distinguish capture/probe faults from core faults; audit actual port consumers; distinguish generated HDL from maintained source; preserve physical packing and latency when reusing tile helpers. The missing-ROM and Windows frame-dump lessons also prevent treating old screenshot artifacts as boot evidence.
- AI JOTEGO is an independent engineering reference, not an endorsement. Local comparisons below are **corpus observations**; risk prioritization is **engineering synthesis**. No new maintainer requirement is attributed to an unverified review comment.

Local machine receipts and raw logs are under `ver/audit/results/` (ignored by Git). `baseline-hashes.json` records the exact pre-edit tracked-file bytes, including the dirty dependencies. `identities.json` records the generator, reference source and critical dependency hashes. The ordered lint input is preserved as `audit-sources.f`; do not replace it with a regenerated list when reproducing this receipt.

| Identity | SHA-256 |
|---|---|
| Local JTFRAME executable | `22f06892797429b0aad73cad8755fe5cb95d27d5a248da4447f97ceece430600` |
| `doc/moo.cpp` | `8ad23bcee1e45985ec40f3242834c8bf612ed1964df5f14f931ba139351ef109` |
| `doc/k054338.cpp` | `e7ed935b266b5f553b9f880c78c8ff0312432570206a84a8a96333a08ed7a301` |
| Dirty shared `jt05415x.v` | `b9509321ae7548c43d198b1e5980df58cbc8182ceb044779731b574e6620c289` |
| Dirty shared `jtsimson_obj.v` | `c59d53e068449e90dce7ff39604ee50e321394034461b3c4cabdbacc6e0e3cd2` |

## Comparison with local jtcores

Counts include locally generated module files and therefore describe this checkout, not just tracked source.

| Core | Local HDL modules / lines | Relevant precedent | Assessment for Moo |
|---|---:|---|---|
| Moo | 12 / 3,173 | Nine maintained modules and three generated register files | Compact integration; the 830-line local PCM file is the main outlier |
| Riders | 20 / 3,768 | `_game`, `_main`, `_video`, `_sound`, `_obj`, `_colmix`; shared `jtaliens_scroll` | Same overall role split; useful protection bus-arbitration and dump precedent |
| Simpsons | 14 / 3,032 | `_scroll` composes K052109/K051962; reusable K053246 objects and K053251 mixer | Best existing object/priority and debug-mux comparison; different tile chips |
| Run and Gun | 13 / 2,376 | Separate CCU, video, dimmer, PSAC and line-buffer control | Best local K053252 cadence/interface comparison; different graphics hardware |
| X-Men | 5 / 1,240 | Small game/main/sound/video/colmix composition through borrowed blocks | Shows that reuse, not matching the number of files, determines a good split |

Moo's maintained module names match filenames. `jtmoo_game` uses `jtframe_game_ports.inc` and named connections. Generic chip filenames such as `jt054338.v` are consistent with local precedents such as Riders' `jt054321.v`; renaming them merely for visual consistency is unnecessary.

### Tile and video structure

```text
jtmoo_game
  jtmoo_main                 CPU decode, DTACK, EEPROM, K053990 bus owner
  jtmoo_sound                Z80, YM2151, K054321, local K054539
  jtmoo_video
    jtk053252                programmed sync/blanking/interrupt generation
    jtmoo_scroll             board-facing bus and raster-coordinate wrapper
      jt05415x               K054156/K054157 registers, page/line access
        jt054157             four independent layer draw pipelines
          jtframe_8x8x4_packed_msb + jtframe_tilemap (per layer)
    jtsimson_obj             shared K053246 sprite/DMA path
    jtmoo_colmix             board palette wiring, foreground and effects
      jtcolmix_053251 + jt054338
```

The tile module uses four 32-bit ROM ports and packed 8×8×4 pixel conversion. That is already a JTFRAME-style arrangement. Simpsons/Riders use older chip families; replacing Moo's register/page logic with theirs would change hardware semantics. Keep chip register interpretation, board glue and pixel-format adaptation distinct. The main risk is the phase contract between CCU, coordinates, shared fetch scheduling, objects and palette—not directory naming.

## Findings and required action

### AUD-01 — P1: vertical coordinate counts HS width instead of lines

**KNOWN behavior in a focused real-module simulation.** `hdl/jtmoo_scroll.v:117-118` resets `hdump` while HS is high and increments `vdump` on every enabled pixel during HS. The upstream CCU connection supplies a sync *level*: `cores/rungun/hdl/jtk053252.v:118-126,177-179` creates programmable-width sync using a counter and JK state.

`tb_video_contracts.sv` applies one HS pulse spanning eight pixel enables at one pixel per six system clocks. The result is `vdump=8`; the line-coordinate invariant requires one increment. This is the first incorrect coordinate producer; tile offsets or sprite offsets would not repair it.

**Next repair:** establish the exact board line origin against CCU `hld`/`vld` or a proven sync transition; update only the board-facing counter contract. Do not choose an edge just because the picture looks better. Test programmable HS/VS widths, 512-pixel wrapping, global flips, line/page boundaries, objects and blanking; require clean MAME/RTL or board-aligned replay and fresh production synthesis. This is L3, not cleanup, and was not patched here.

### AUD-02 — P1: background red and blue are interchanged

**KNOWN behavior in the focused real-module simulation.** `hdl/jt054338.v:56` produces `{R,G,B}`. `hdl/jtmoo_colmix.v:183` assigns that word directly into `bgr`, while line 83 drives `{blue,green,red}=bgr`. Palette branches already explicitly assemble BGR. The local reference describes register 0 as red and register 1 as green/blue (`doc/k054338.cpp:12-13,112-115`).

The diagnostic programs background `0x123456`, brightness level `0xff`, and video enable. Accounting for the existing multiply/256 brightness arithmetic, expected RGB is `0x113355`; observed RGB is `0x553311`. The error is localized to the background packing boundary. This test does not establish that the existing brightness formula itself matches silicon.

**Next repair:** correct that boundary alone under the hardware-change workflow. Test asymmetric primary colors, background-only, foreground bypass, normal/additive blend, shadow, brightness and video disable. Do not swap global outputs, which would regress the palette paths. No RTL change was made.

### AUD-03 — P1: scene-only configuration does not compile

**KNOWN compiler failure.** `ver/moomesa/sim.sh --scene` selects `NOMAIN`/`NOSOUND`. In `hdl/jtmoo_main.v:340`, the `NOMAIN` branch assigns `reg_cs`, but its declaration is inside the excluded normal branch at line 79. Fresh focused lint reports `Can't find definition of variable: 'reg_cs'` and exits 1.

The branch also lacks explicit producers for several public outputs, including `ram_we`, `rw`, `oram_we`, `scr_cs`, `scrreg_cs`, and `cco_cs`. Removing the illegal assignment alone is insufficient. Its placeholder `saved`, `f`, and `fcnt` do not restore main state.

**Next repair:** define the intended scene-harness contract and drive every output, preserving required state restoration. Elaborate normal, NOMAIN, NOSOUND and combined variants, then run a real captured scene. Leave source changes outside lexical cleanup.

### AUD-04 — P1: inherited dump layout cannot represent Moo's state

**KNOWN address/capacity mismatch from source.** `jtmoo_video` instantiates `jtriders_dump #(.FULLRAM(1))`. That layout allocates 24 KiB scroll + 4 KiB palette + 8 KiB object + 33 bytes of registers (`0x9021`), matching the debug `JTFRAME_IOCTL_RD+=36897` in `cfg/macros.def`.

- Moo's palette has 2,048 entries (`jtmoo_colmix`, three `AW(11)` byte RAMs), serialized as x/R/G/B: **8 KiB**. Its dump input is only 12 bits and `pal_addr` explicitly forces the high bit to zero at line 101. The upper 1,024 colors cannot be read through this path.
- The object instance uses `RAMW(13)` and a 14-bit byte-dump address, but the inherited default `FULLOBJ=0` allocates only 8 KiB. The full CPU-visible 16 KiB object store is not represented.
- The inherited palette-register segment is only `0x9000..0x900f`. `ioctl_addr[4]` is zero throughout it, so `jtmoo_colmix`'s K054338 dump selector never selects that chip during the allocated segment. The extra register mirror is therefore not proof those registers can be captured.
- The generic splitter expects a single `pal.bin` and its high/low halves. Moo's live palette memories restore separate `pal_r.bin`, `pal_g.bin`, and `pal_b.bin`. The old format cannot provide a complete round trip.

**Next repair:** write a Moo-owned serialized-state schema with sizes, offsets, channel ordering, register banks and matching capture/restore consumers. Update HDL, macro length and splitter together, then prove a sentinel-pattern round trip covering the upper halves. No shared Riders file should be edited to impose Moo's format. Capture-generated discrepancies must be excluded before differential RTL work.

### AUD-05 — P2: main/video debug paths terminate unused

**KNOWN source and lint finding.** `jtmoo_game.v:22,30-32` collects `st_main` and `st_video` but always selects `st_snd`. Strict lint reports both unused. This hides CPU IRQ/DMA status and the video/dump status mux. `debug_bus` is also unused inside `jtmoo_main`.

Simpsons selects main/video/sound using `debug_bus[7:6]`; Riders has a similar main/video/profile mux. Run and Gun also currently selects sound only, so this is a concrete observability deficiency, not a claim that every accepted core follows one style.

**Next repair:** restore an explicit debug selection contract, verify all selections against changing producers and preserve the register-read addressing bits. This changes an observable hardware interface and needs its own verification/synthesis gate.

### AUD-06 — P1 verification gap: PCM scheduling and protocol limits

**KNOWN architecture, unproven failure hypotheses.** `jtmoo_k054539` is a core-local, explicitly provisional implementation; it is actually instantiated and is not the silent `modules/jt539/hdl/jt539.v` placeholder. The local placeholder must not be mistaken for a tested donor.

- The 384-CEN sample counter free-runs, but processing starts only in `S_IDLE` at count zero; ROM latency, large pitch steps or repeated terminator/loop reads can exceed the slot. CPU data-port service is also admitted only during selected idle slack (`sample_cnt<320`). No deadline/maximum-wait assertion exists in the maintained core.
- Playback may keep `sample_rom_cs` asserted while changing address on a completed low-byte or loop read. That needs an explicit contract with the real SDRAM cache's ready behavior; do not assume a one-cycle response or diagnose a duplicate byte from source alone.
- The synthetic Z80 stall is explicitly different from the board's unconnected WAIT pin. Data correctness does not establish command/IRQ cadence equivalence under contention.
- Registers are initialized once but not all reset with the sequencer. Warm-reset retention versus cold initialization needs a documented device contract and directed test.
- Fixed-point widths are explicit (16-bit samples, 17-bit volumes, 34-bit products, 40-bit accumulators, 17-bit AUX sum and saturation). However AUX `VOLSHIFT(1)`, final gain 1.99, reverb behavior, analog RC values and the copied MAME double-position reverb interpretation still need exact evidence and quantitative regression receipts. Do not tune these by ear.

**Next tests:** eight active voices, maximum legal pitch, all sample formats/directions, loop terminators, key-on during retire, key-off during read, concurrent data-port traffic, randomized legal SDRAM backpressure, warm reset, and full-scale/impulse/phase/clipping measurements. Prove a missed deadline or handshake error before changing arbitration or pipelining. No resource optimization is justified without fresh synthesis evidence.

### AUD-07 — P2: source closure and generation are not fully reproducible

**KNOWN generator behavior in this checkout.** Fresh native `jtframe mem` and `jtframe files` succeeded. A second memory-generation run produced byte-identical wrapper and port include. The second source-list run produced the same **242-file multiset but different ordering**. Strict lint also reports four duplicate module definitions (`jtframe_dual_nvram` and three SDRAM64 helpers).

The default `lint-one.sh` deletes its `ver/lint` workspace and invokes shared `jtsim` policies. This audit instead used the native generator in a unique core-owned results folder and the inspected Verilator MCP safe launcher; no shared script was modified. Existing `ver/moomesa/filtered.f` had mangled Windows paths and was not used.

`cfg/files.yaml` still requires the uninstantiated `jt539` package. Removing a source dependency is conditional L2 work: verify every mode and target, including generated audio metadata, before removing it. The local binary's provenance and the dirty shared modules are explicit build-identity limitations.

**Next action:** retain ordered closure digests per run; resolve the ordering/duplicate-path issue in the owner only when that write scope is separately authorized. Rebuild generated register inputs from a clean checkout and compare hashes. Do not silently use old generated MMR files as a reproducible build claim.

### AUD-08 — P2: documentation and source provenance are incomplete

**KNOWN documentation gaps.** The original README listed the parent game only and did not explain the local PCM implementation, configuration variants, hardware requirements, OSD features or validation limits. The audit update adds those distinctions.

`doc/moo.cpp` and `doc/k054338.cpp` have retained original notices but no immutable upstream revision manifest. No core-local `doc/mame.xml` exists; JTFRAME may use its shared database, but agreement between that database and these source snapshots is not established. `cfg/mame2mra.toml` advertises four Moo variants through the driver and excludes Bucky/bootlegs. MRA generation/validation and distribution completeness were not certified here.

**Next action:** pin upstream revisions and hashes for imported/adapted files, the PCM interpretation and numeric tables. Document every actual set and skipped family. Do not invent Jose Tejada authorship for the local model or call the provisional implementation shared jt539. No copyright/header metadata was rewritten.

### AUD-09 — P3: limited presentation cleanup remains

The static tool reported 3 major, 6 minor and 3 informational findings over 12 local HDL files. Manual disposition:

| Pattern finding | Disposition |
|---|---|
| Missing legal headers on three `jtk*_mmr.v` files | Generated, ignored HDL; not missing notices in the nine maintained modules. Fix a generator policy if required, never hand-edit generated files |
| Trailing whitespace in those same generated files | Same disposition |
| `jtmoo_colmix.v:93` looks like commented-out HDL | False positive: the MIX pin equation is hardware documentation; retain it |
| Six PCM comments look like disabled HDL | Address mappings and arithmetic/equation documentation; not a blanket deletion target |
| PCM decorative rulers, long comment runs, 22.6% comment density | Some review noise, but many comments carry physical/latency/width evidence; density is not a quota |
| PCM legacy GPL header | Legal/provenance content; retain |

`exp2.hex` and `log2.hex` are byte-identical to Riders' tables and have no functional consumer in Moo's maintained RTL. They are cleanup candidates after full manifest/QIP/generator-use review, not automatically removable files. `sch/moomesa/moomesa.kicad_prl` is tracked local editor state; consider excluding it in a separate repository-hygiene change.

The generated K053251/K054338 mirrors are observation-only, not second live mixers. They do consume state and duplicate register interpretations; AUD-04 must be repaired before claiming their usefulness or replacing them with direct taps. Avoid a broad reformat, state-machine rewrite, signal rename, or declaration removal under a cosmetic label.

## Per-subsystem review coverage

| Area | What was checked | Unclosed verification |
|---|---|---|
| Game integration | Standard include, named ports, main/video/sound boundaries, generated memory ports | Debug selection; per-target lint and hardware output |
| Main CPU | Single default-low decoder, bus-owner mux, DTACK busy sources, byte strobes, PAL labels | Exhaustive decode aliases, interrupt priority/order, pause with DMA, reset/X matrix |
| Protection | Byte-lane register writes, edge trigger, zero count, read/read/write sequence, BR/BG/BGACK | Hardware cadence and bus-release edge proof; held/early/late DTACK, reset in every state, overlapping DMA ranges |
| EEPROM/inputs | Three-button config, four joystick buses, service/test mapping, 128-byte memory | All four sets, cold/default EEPROM, reload/soft reset/service, persistence round trip |
| CCU/scroll | Shared device boundary, programmed sync, four layers, physical packed-format adapter | AUD-01; page/line/flip and line-scroll timing against a pinned reference |
| Objects | Shared K053246 hierarchy, 16-bit profile, A6/A7 omission, address/ROM widths | Dirty shared baseline, 256-entry load/budget, ROM stalls, priority/flip/wrap, full dump |
| Palette/mixer | xRGB CPU lanes, separate RGB RAMs, foreground bank 0x700, CI wiring, shadow/blend math | AUD-02/AUD-04; stage-by-stage latency, boundaries, brightness/clip behavior |
| Sound | PAL-qualified Z80 decode, bank latch, IRQ/NMI, PCM busy feedback, AUX routing | AUD-06; PCM/IRQ/timer and analog reference tests |
| Memory/resources | Flat arrays, declared widths, memory generator, three palette planes, two reverb banks | Physical depths/aliases versus allocation; fresh Quartus inference/fit; no utilization claim |
| Configuration/MRAs | Header size 16, ROM region ordering/widths, four-set defaults, target skips | Fresh MRA XML validation, ROM hashes, download bytes/DDR address and all-set boot |
| Verification/repository hygiene | All tracked core scripts, generated-file distinction, neighboring tests, strict lint | Functional regression suite is insufficient; no complete cold-start/gameplay acceptance |

Most core state is on one system clock with enables; this does not replace a complete framework-to-core CDC inventory. The local audio clock generator is named `clk48`; target-domain assumptions must be tested for Pocket/SiDi128 rather than inferred from MiSTer alone.

## Changes made in this audit

| Files | Change and proof |
|---|---|
| `ver/game/dump_split.sh` | Forward all arguments and use a script-relative delegate path with the same Bash interpreter |
| `ver/moomesa/sim.sh` | Propagate failures; reject missing NVRAM/scene name; preserve argument boundaries; forward batch; require frame+CRC; handle PNG/JPEG without lying about extension; preserve existing CRC unless explicitly updated |
| `ver/moomesa/sim_coin.sh` | Stop immediately if conversion/simulation/artifact handling fails |
| `ver/audit/test_scripts.py` | Twelve isolated mock-tool tests; no simulator or copyrighted media |
| `ver/audit/tb_video_contracts.sv` | Real-module synthetic counterexamples for AUD-01/AUD-02; intentionally fails on current RTL |
| `ver/audit/.gitignore` | Keep receipts, logs, generated local inputs and Python cache out of source control |
| `.gitignore`, `.gitattributes` | Expose only the new audit sources through the repository's blanket `ver/` ignore rule; keep the three touched shell scripts in LF format without changing global Git rules |
| `README.md`, this file | Evidence-scoped user/developer documentation |

Script decision record: observation = wrong exit status/argument transport; evidence = eight pre-edit failing mock tests; competing hypothesis = unavailable real simulator, excluded by fake-tool execution; selected producer = shell wrapper; smallest change = the three shell files; verification = twelve post-edit tests; regression scope = wrapper consumers and JPEG/PNG/CRC paths; unknowns = full scene-state compatibility remains AUD-03/AUD-04. No HDL/configuration mutation was undertaken.

## Commands and results

| Gate | Result |
|---|---|
| `jtcode_audit.py --root D:/jt/cores/moo` | Completed, findings dispositioned above; static pattern results are not hardware proof |
| `jtframe mem moo --target mister --local` | PASS twice; wrapper and port include byte-identical |
| `jtframe files sim moo --target mister --local -m SIMULATION,VERILATOR` | PASS twice; same set, order differs (AUD-07) |
| `jtframe cfgstr moo --target mister --output verilator --def SIMULATION,VERILATOR` | PASS; exact defines saved |
| Strict `--lint-only -Wall --assert --timing --sched-zero-delay --x-initial unique --x-assign unique --threads 1` on `jtmoo_game_sdram` | FAIL: 754 warnings; no normal-lane syntax, width, latch or undriven diagnostic in this receipt |
| Focused `jtmoo_main +define+NOMAIN` lint | FAIL: undeclared `reg_cs` |
| Original wrapper tests | 8/8 failed, each for a reproduced wrapper contract violation |
| Final wrapper tests | 12/12 passed, including CRC mismatch/update and PNG preservation |
| Shell syntax and final whitespace checks | `bash -n` for all three scripts and `git diff --check` passed |
| Video diagnostic | Built and executed twice from reset; both runs FAIL at AUD-01/AUD-02 with identical stdout |
| MRA/msg/MMR regeneration, other target builds | Not certified; generated MMR baseline was preserved |
| Full boot/attract/coin/service/gameplay/audio/MAME comparison | Not run as acceptance; no deterministic full-game result claimed |
| Quartus / RBF / hardware | Not run; no synthesizable source change or final-RBF request |

Strict lint distribution: EOFNEWLINE 87, MODDUP 4, PINCONNECTEMPTY 214, DECLFILENAME 22, TIMESCALEMOD 47, GENUNNAMED 52, VARHIDDEN 8, UNUSEDSIGNAL 258, UNUSEDPARAM 31, PROCASSINIT 29, SYNCASYNCNET 2. These include shared dependencies, generated files and intentionally open outputs. Do not convert the total into 754 functional defects or suppress it wholesale.

The video diagnostic retains `-Wall` output but uses `-Wno-fatal` solely to execute counterexamples despite existing warnings. It is **diagnostic**, not a warning-free acceptance result. Assertions, timing and strict X options remain enabled. An initial C++ link failed with unresolved libstdc++ move-constructor symbols; the separate build using the documented `-O3 -CFLAGS "-O3 -march=native"` completed. The first testbench draft incorrectly used pixel enable every system clock and did not configure brightness; its background result was rejected. The final test uses six system clocks per pixel and accounts for brightness. No earlier failed build or draft run is treated as accepted evidence.

Final video stdout SHA-256: `2d41d3554e5048edd3ba61844c28ef648ffab5b015d1ecc4f186c647f5aec57e`. Its failure is at the synthetic 1,560 ns stop, not a native game-frame barrier. Synthetic RAM fixtures contain zeros, not ROM data. There is no pinned MAME golden, matching-prefix claim or closed accuracy divergence from this task.

Tools: Verilator 5.050 (`2026-07-01 rev vUNKNOWN-built20260702`), native UCRT64 compiler; MCP `verilator_preflight`, `verilator_workspace`, and `verilator_project_run` used with headless=true, display_backend=none, runtime_threads=1. Real module sources and exact command/build/run receipts are retained. No SDL/display code, gameplay observer, generic MCP-generated testbench or MAME session was used. The short unit run needs no long-run checkpoint.

Re-run wrapper tests from a configured Python/Bash environment:

```text
python cores/moo/ver/audit/test_scripts.py --bash <path-to-bash> -v
```

Re-run the video counterexamples using the command in `results/video-final-build/receipt.json`, a newly allocated safe R: workspace, and the safe simulator launcher. Keep the generated include, defines, ordered source list and their hashes together. R: executables are volatile; a stale workspace pointer is not a runnable result.

## Repair order

1. Repair the scene evidence path (AUD-03/AUD-04) and retain the failing video tests.
2. Close the line-coordinate producer AUD-01 under a pinned board/reference phase contract; then rerun full video and prior regressions.
3. Close the isolated background packing defect AUD-02, with mixer regressions and synthesis.
4. Restore useful debug selection and establish the PCM timing/handshake/reset matrix.
5. Pin/import evidence, clean source generation and warnings, then finish four-set and supported-platform acceptance.
6. Perform lexical cleanup only after the warning/verification baseline is usable; never remove physical evidence or tool directives to meet a comment percentage.

Final self-review: no architectural block, width, signedness, state, clock enable, reset, CDC, SDC endpoint, ROM map, raster, gain, vendor IP or license was changed. No workaround was removed. Shared and sibling-core changes were preserved byte-for-byte relative to the initial snapshot. MiST/SiDi remain explicitly skipped by the core; Pocket/SiDi128 have no new validation claim. The user-facing result is **audit complete; script cleanup tested; functional and submission blockers remain**.
