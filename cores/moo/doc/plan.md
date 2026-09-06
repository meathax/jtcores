# Moo Mesa core completion plan

**Primary work plan — development, acceptance gates still open.** Audited against the working RTL on 2026-09-05. [audit.md](audit.md) is the original audit; [fix-ledger.md](fix-ledger.md) contains historical implementation evidence. Their older status rows do not override this inventory. [plan-baseline.md](plan-baseline.md) identifies the audited files and dirty shared dependencies. Hashes identify inputs, not correctness.

This revision is documentation only. It does not accept unfinished changes or initiate another build, simulation or deployment. The next executor must compare current files with the baseline before using old receipts.

## 1. Scope, authorization and completion

Only modify **D:/jt/cores/moo**. Other cores, modules, JTFRAME, installed tools and vendored IP are read-only. The user permits changes to other main folders only when pulling the latest jtcores from GitHub; this plan does not schedule a pull. Preserve existing changes in `cores/simson/hdl/jtsimson_obj.v` and `modules/jt05415x/hdl/jt05415x.v`; both affect Moo's dependency closure. Never reset, clean, discard, commit or push without explicit authorization.

The user has provided a MiSTer at **192.168.0.69** and authorized RBF builds for testing whenever needed. Connection, credentials and physical output have not been verified. This is standing user authorization for future testing, subject to the applicable build skill and tool contracts. Do not ask again for already authorized ordinary work. Ask only for inaccessible credentials, physical interaction or an out-of-scope change. Do not publish without authorization.

The core is complete only when:

- Every defect has a reproducible closure or an evidence-backed non-defect disposition. Unknowns are not relabeled PASS.
- Deterministic full-core scenarios cover boot, attract, inputs, service/test, gameplay transitions, resets and prolonged activity; earlier failures remain regressions.
- Native-frame reference/RTL comparisons reach declared stop barriers. A hardware-correct reference exception requires stronger evidence and is not called MAME equivalence.
- Production manifests, inference, fit, timing and compressed-artifact acceptance pass for the same source/configuration.
- That exact RBF is tested on the MiSTer for display, sound, controls and settings persistence; known-good rollback remains available.
- All four advertised sets have validated MRAs and test dispositions. Documentation, provenance, licenses, targets and artifact hashes agree.

A map, module test or plausible screenshot alone cannot close the core. No final RBF acceptance exists from this audit.

## 2. Instructions for Luna, Terra and future sessions

1. Read this plan, applicable AGENTS instructions, shared lessons and the relevant skill. Search lessons by the actual subsystem/failure. Use AI JOTEGO guidance with its source context; it is an independent compilation, not Jotego endorsement.
2. Read Git status and compare relevant baseline hashes. Preserve all edits. Do not edit generated HDL, databases or reports. Use CodeGraph first if indexed; otherwise make focused searches.
3. Select the first eligible packet. Record its baseline and next falsification test. Apply one causal correction at a time. The first trustworthy accuracy divergence takes priority over a guessed subsystem order.
4. Discover current MCP operations and exact schemas. Prefer compatible real-harness, headless operations. Record concrete capability gaps before a CLI fallback. Success text is not an evidence receipt.
5. Run the focused baseline before editing. Publish: Observation; Evidence; Hypotheses; Selected explanation; Smallest change; Verification; Regression scope; Known unknowns. Label claims KNOWN, INFERRED or HYPOTHESIS. If the producer is unproven, instrument or falsify first.
6. After each synthesizable edit, run focused regression and fresh production Analysis & Synthesis through the global runner before accepting the iteration or continuing dependent work. Do not wire unused signals into functional outputs to silence warnings.
7. Save commands, exits, source/tool/ROM hashes, warnings, assertion results, barrier reached and artifact hashes. Preserve full logs separately. Verify complete checkpoints before intentionally stopping expensive healthy runs.
8. Update packet status and the iteration ledger: what actually ran, active mismatch, exact next experiment. Distinguish compiled, simulated, compared, synthesized and hardware-tested.

Use Context Mode for large trees, diffs and logs. Durable project evidence belongs under `ver/audit/results/<packet>/<run>`. Bulk generated simulation state belongs in a unique safe-launcher `R:/Verilator` workspace; pointers may be stale after reboot. Never reuse a model merely because its name matches.

Acceptance runs use one runtime thread, assertions, strict timing and unique-X semantics. Module diagnostic waivers are not a full-core clean-lint verdict. The real gameplay harness stays headless and deterministic; any permitted observer is a detached presentation process. Resolve legacy display-wrapper conflicts using the current headless contract, not SDL/dummy-driver substitutions.

## 3. Audited status and evidence limits

| Item | Current state | Remaining proof |
|---|---|---|
| AUD-01 raster | Open: `jtmoo_scroll` increments `vdump` repeatedly while HS is high | Physical CCU line/frame phase and causal correction |
| AUD-02 background color | RGB/BGR boundary corrected; focused seeds 1/17 and map passed | Full mixer/game and MiSTer regression |
| AUD-03 NOMAIN | Isolated idle outputs repaired; reset/idle bench passed seeds 1/17 | Combined NOMAIN/NOSOUND restored scene |
| AUD-04 dump/restore | Partial candidate; serializer and palette tests passed | Source visibility, new loader, integrated round trip, current-source map |
| AUD-05 debug | Game status still exposes PCM only | Selector preserving all video register banks |
| AUD-06 PCM | Provisional core-local implementation | Handshake, cadence, arithmetic, reset and audio equivalence |
| AUD-07 production | Core-local generation and map work | Stable closure and complete acceptance tooling |
| AUD-08 sets/provenance | Four MRAs and ROM sets audited | Reference version agreement and immutable provenance |
| AUD-09 cleanup | Deferred low-priority candidates | Proven dead dependencies, final style/claims review |

Evidence anchors, requiring identity checks before reuse:

- HEAD `8248dc6c3414dcd251be2778f80c82da78103acf`; working tree is dirty.
- MAME `D:/Arcade/AI/mameexe/mame.exe`, 0.289, SHA256 `af6966108d9b52c22465c6d50f4e5d50cc371b50f2d27dc443935f287aad37a3`.
- Existing private ROM directory audited for all four sets: `D:/vibes/fpga/temp/moomsa-mra2rom-audit-20260824T062142Z-919/zips`. Recheck availability/hashes. Never download, distribute or commit ROM images.
- `ver/audit/results/dump-fix` contains palette before/after, serializer and workspace receipts. Upper-palette baseline failed at entry 1024, lane 1: actual 00, expected 4c. Corrected test covers 8,192 palette bytes plus 45 live register bytes. Latest extended test has one recorded seed; earlier color-only seed coverage does not transfer automatically.
- Serializer test traversed all 65,536 video addresses. Python scene tests passed 3 cases; shell adapter tests passed 12. These are not an integrated upstream-memory round trip.
- Latest map: `ver/audit/results/production/.codex-mister-build/jtmoo/20260905-134058-426-map`, exit 0; 54,215 logic cells, 1,617 RAM segments, 65 DSP elements, 3 PLLs. These are synthesis figures, not placed utilization/timing. This predates the latest SIMULATION scene-loader addition.
- Earlier maps used 54,246 logic cells. The 31-cell reduction is not a timing claim. Approximately 16,903 warnings remain in the production report; there is no blanket clean-diagnostics verdict.
- Intermediate object-RAM “uninferred” messages did not prove a resource defect: final per-entity results showed two 16,384-bit RAM halves with zero own logic/register cost. Do not rewrite RAM on that message alone.

No paired live MAME/RTL lockstep or MiSTer verification was completed by this audit. Historical receipts remain diagnostic/focused evidence within their exact scope.

## 4. Architecture and sibling-core alignment

Keep the existing JTCORES `cfg/`, `hdl/`, `ver/`, `doc/`, `pal/`, `sch/` structure. This is not a new standalone MiSTer repository. Do not copy another `sys/` tree or convert it to a standalone template. Generate target projects through JTFRAME.

| Function | Current implementation | Comparison/action |
|---|---|---|
| Integration | `jtmoo_game`, memory/macros configuration | Compare generated clocks, memories and actual fan-out with sibling JTCORES |
| Main CPU | `jtmoo_main`, JTFRAME 68000/DTACK | Validate with 055373 PAL and board address pins |
| Protection | `jtmoo_prot` | K053990 transactions, arbitration and original program behavior |
| Scroll | `jtmoo_scroll -> jt05415x -> jt054157 -> jtframe_tilemap`, packed-MSB helper | Already uses the newer tile family; older Simpsons/Riders are not drop-in chips |
| CCU | Rungun `jtk053252`, generated MMR | Compare programmable timing/CEN/load strobes; prove Moo glue independently |
| Objects | Simpsons `jtsimson_obj`, `jt053246` scanner/DMA/MMR | Test Moo address wiring, deadlines and line ownership; shared dirty code is read-only |
| Color | Simpsons `jtcolmix_053251`, local `jt054338`/`jtmoo_colmix` | Verify priority, shadow/brightness, packing and companion latency |
| Sound | `jtmoo_sound`, Riders `jt054321`, Z80/jt51 | Explicit decode, access strobes, wait paths and FM cadence |
| PCM | Local `jtmoo_k054539` | Prove provisional implementation; do not replace it with a silent stub |
| Capture | `jtmoo_dump`, `ver/game/scene.py` | Moo's larger palette/object state needs its own serialization contract |

Before structural changes, record actual sibling paths and immutable revisions, hierarchy, memory packing, CEN/reset and latency, plus why board glue permits reuse. Matching style does not justify changing hardware. Do not move files or add latency merely for visual similarity.

## 5. Work order

Default order: **P00 -> P01 -> P02 -> P03 -> P04 -> P05 -> P06 -> P07 -> P08 -> P09 -> P10**. P03 discovery and P09 capability investigation can happen earlier without RTL changes. Once a trustworthy differential mismatch exists, its earliest causal producer governs the functional order. Record changes of order; do not skip unresolved earlier mismatches.

### P00 — Reproducible source and build closure

**In progress.** Source visibility is repaired; independent generation exposed source/port-order and timestamp nondeterminism. See [completion-progress.md](completion-progress.md) and `ver/audit/results/p00/closure-comparison.json`. P00 is not closed. Allowed edits: core ignore rules, core-owned adapters/manifests/evidence.

1. Root `*_dump.v` currently hides `hdl/jtmoo_dump.v`. Verify with `git check-ignore -v cores/moo/hdl/jtmoo_dump.v`; add a narrowly scoped core-local unignore or equivalent visibility solution. Do not edit root ignore rules. Verify the new source appears in Git status; no commit is requested.
2. Inventory all eleven Moo entries in `cfg/files.yaml` against synthesis and simulation closure. `jtk053252_mmr.v` is generated: regenerate through its configured flow, never hand-edit it.
3. Confirm removed generated K053251/K054338 observation mirrors cannot re-enter through a wildcard. Ignored stale generated files on disk are not live implementations.
4. Generate twice in isolated core-owned directories. Compare ordered transitive paths, hashes, macros, generated inputs and package order. Normalize unstable generator output only when semantics are preserved; never blindly sort HDL.
5. Audit the `jt539` manifest dependency for actual instantiation. Remove it only as a separate proven-dead dependency change with equivalent elaborated hierarchy.
6. Run current Python checks and preserve the baseline. Inspect exact executed commands; a script exit 0 is not proof it launched the intended model.

Exit: required sources are version-control-visible, closures contain exactly the intended hierarchy, and a fresh build needs no legacy cached model.

### P01 — Finish dump/restore integration (AUD-04)

Allowed files: local dump/video/colmix/K338/scroll, related cfg, `ver/game` and audit tests. Shared devices remain read-only.

Current version-1 map, relative to video bytes after the **128-byte EEPROM prefix**:

| Inclusive range | Contents | Bytes |
|---|---|---:|
| 0000–1fff / 2000–3fff / 4000–5fff | Three scroll RAM banks | 8192 each |
| 6000–7fff | Palette x/R/G/B | 8192 |
| 8000–bfff | Object RAM, low byte first | 16384 |
| c000–c03f / c040–c047 | K054156 / K054157, low byte first | 64 / 8 |
| c048–c07f | Zero padding | 56 |
| c080–c08c | Live K053251 registers | 13 |
| c08d–c09f | Zero padding | 19 |
| c0a0–c0bf | Live K054338, low byte first | 32 |
| c0c0–c0c7 | Object diagnostic registers | 8 |
| c0c8–c0cf | Zero padding | 8 |
| c0d0–c0df | CCU registers | 16 |
| c0e0–c0ef | MOOSCENE + version 1 + seven zero bytes | 16 |

Video length is 49,392 (0xc0f0); total is **49,520 bytes**. Later video addresses return zero. Old 37,025-byte dumps cannot recover missing state; reject them rather than invent padding.

The candidate removes Riders serialization, exposes all 2,048 palette entries, reads live color registers and separates the two tile-register filenames. `scene.py` extracts files and hashes them. This is a display scene, **not a CPU/audio checkpoint**. Shared object restore forces configuration byte 5 bit 4 and does not restore `rmrd_addr`; determine and document the scene-mode consequences.

Next steps:

1. Repeat palette/register and serializer tests with seeds 1/17. Refresh raw diagnostic inventory: line-based waivers may be stale after source insertion. Preserve the upper-half baseline failure.
2. Test the new SIMULATION K054338 loader: absent file, exact asymmetric 32-byte file, short file, trailing bytes, cold and repeated reset. `$fread` into a fixed array can ignore excess data; prove strict size validation. This loader is untested.
3. Fill real scroll/palette/object memory through CPU/write ports, including both lanes and each last word. Capture through actual video/game IOCTL, parse, restore into a fresh simulation, compare contents/registers and the first stable native frame. Hierarchical force is not sufficient round-trip evidence.
4. Verify EEPROM prefix, total download/read length and mux latency. Exercise 5fff/6000, 7fff/8000, bfff/c000, c09f/c0a0, c0df/c0e0 and end-of-stream boundaries.
5. Test interrupted extraction. Preserve an existing valid scene until all new files and manifest are complete; reject mixed-generation files through hashes.
6. Run combined NOMAIN/NOSOUND hierarchy and actual scene replay, then normal production elaboration. Distinguish file-backed simulation reset from physical reset.
7. Fresh production map on the exact final source; inspect inference/resource changes and update the ledger.

Exit: integrated exact round trip, strict malformed-input behavior, explicit state limitations, no duplicate live register mirrors, and production behavior preserved. Serializer PASS alone does not close this packet.

### P02 — Reachable debug status (AUD-05)

`jtmoo_game` exposes only `st_snd`. PCM uses debug bit 0; video uses bits 5/4; palette uses bit 7 for its K338/K251 bank. A naive top-level 00/01/10/11 high-bit mux hides one video bank.

1. Enumerate all meaningful selectors and addresses. Prove reachability of 32 K338 bytes, 13 K251 registers, tile/object status, main status and both PCM values.
2. Choose routing from that table. Two video ranges preserving bit 7 are a possible experiment, not an accepted implementation.
3. Sweep selectors using distinct source values and actual consumers. Prove diagnostics do not change game/audio/timing/RAM behavior.
4. Fresh map; update README's sound-only statement only after tests pass.

Exit: all advertised diagnostics reachable without address collisions or functional side effects.

### P03 — Real deterministic reference lane

1. Read `mister-mame-diff` and its live-lockstep protocol. Inspect MCP support for exact input journals, headless participants, native-frame barriers, complete save/restore and artifacts. Record fallback reasons.
2. Pin reference source/binary, driver, ROMs, EEPROM, configuration, reset/clocks, compiler, RTL closure, harness/exporters and comparator. Resolve MRA metadata 0282 versus MAME 0289 by comparing actual driver/ROM metadata and selecting one contract, not simply editing a label.
3. Build the real Moo SoC harness: CPU, SDRAM latency, loader, inputs and persistent state. Old `obj_dir`, ROM conversions and screenshots in `ver/moomesa` are untrusted until fingerprinted. Generic generated benches remain diagnostic.
4. Prove descriptor-to-loader-to-bank byte ordering with reset vectors/checksums. Reset release follows completion and valid EEPROM state.
5. Two independent clean runs per lane must produce identical normalized evidence. Run the declared RTL reset/X matrix. Publish immutable reference evidence only after determinism passes; never select the convenient seed.
6. Couple participants at one exact anchor, release one native frame, validate every declared evidence domain, compare immediately and freeze at first mismatch. Record ordinal, fields, matching prefix, last-good/first-bad context and digests.
7. Save full model/external-state checkpoints before expensive/input-dependent milestones; verify atomic receipts and post-restore fingerprints. Scene dumps do not qualify.

Exit: trustworthy evidence and exactly one active divergence, or a reproducible pipeline defect with a repair task. Never edit accuracy RTL on a tainted exporter, bad ROM map or host-time alignment.

### P04 — Coordinate producer and native raster (AUD-01)

KNOWN: current scroll counters reset horizontal position throughout HS and advance vertical position on each pixel enable with HS high. The focused video-contract bench demonstrates repeated advances for a multi-pixel pulse. The correct replacement phase remains unproven.

1. Trace actual schematic nets and CPU CCU programming. Read Rungun CCU HLD/VLD registration and HBlank/vertical cadence. Those outputs are currently disconnected at Moo. Do not blindly substitute them or assume a sync edge.
2. Observe CCU counters/load strobes, HS/VS, pixel enable, dump coordinates, tile fetch slot, object line request and blanking together. Exercise programmable widths greater than one.
3. Derive totals, sync/blank intervals and coordinate origin from board/device evidence plus clean reference observations. Assert one line advance/frame wrap at the established phases.
4. Apply the smallest producer/glue correction with an explicit latency budget. Cover tile `hdump[2:0]` scheduling and object line timing. No terminal crop, offset or blanket delayed blanking.
5. Run pulse-width, reset, flip and wrap tests, then clean differential replay past the old failure, complete scenario and previous regressions. Require strict prefix advancement and no earlier mismatch.

Exit: native timing and tile/object phase match the contract; actual MiSTer display verification is required before shipping a video timing/reset change.

### P05 — Main bus, protection and memory

Create a Boolean decode/lane table from `pal/moomesa/055373.txt`, schematics and the actual owner-muxed bus. Cover ROM, work RAM, scroll/registers, object RAM/registers/readback, palette, PCU/K338, CCU, protection, cabinet, EEPROM and mailbox. Prove ignored address bits and physical depth separately from CPU window size.

Tests: high/low/both/neither byte enables; aliases; unexpected select overlap; stalls; reset during access; CPU/protection ownership; request stability through acknowledgement; real CPU CEN wait behavior. Investigate raw CPU `RnW/LDSn/A` uses such as `pair_we` and cabinet reads during muxed ownership. These are hypotheses, not confirmed bugs.

Protection-specific tests:

- Current operation is 16-bit wrapping `src1 + 2*src2`, register-triggered DMA with BR/BG/BGACK.
- Exercise zero/one/maximum count, pointer wrap and lane combinations. Trigger currently checks write/address c without explicit lane-valid qualification; establish board behavior before changing it.
- Use a hostile DTACK responder: minimum and varying latency, held acknowledgement and back-to-back transactions. Prove stable address/data, one capture/write per acceptance and correct bus release.
- Probe stale DTACK at request-launch state transitions. Always-ready RAM can hide a sequencing defect.
- Cover reset/IRQ during arbitration, CPU fairness and original program protection transactions. Verify unreset temporary state is written before use under the X matrix.

Trace interrupt polarity/priority and acknowledgement, including active-low DMA-completion state. Do not change polarity from comments alone. Keep every causal fix isolated with its own regression and fresh map.

Exit: decode, lanes, aliases, waits, IRQ and DMA pass through real ownership paths and complete program scenarios.

### P06 — Provisional PCM and sound integration

Preserve sound's real memory-access qualifier `!mreq_n && rfsh_n` and CPU gating by `~k39_busy`. PCM's missing A8 and `{A9,A[7:0]}` mapping are intentional board wiring. Do not replace local PCM with a silent shared stub or promote it into modules.

First inspect generated `cen_pcm`: memory config declares 18.432 MHz with `gate: [pcm]`. Determine how SDRAM waits affect that enable before claiming the 384-enable counter produces a fixed wall-clock sample rate.

Build focused tests for:

1. Register readback/mirrors, once-only write-release capture, CEN-low writes, reset retention, key on/off, UPDATE_AT_KEYON and live positions.
2. Eight voices; 8-bit, 16-bit little-endian and DPCM; signed extremes; forward/reverse; fractional pitch; loop and 80/8000/88 terminators; ROM boundaries.
3. ROM request/address stability and one byte per accepted response, consecutive 16-bit reads, delayed/held `rom_ok`, data-port/sample contention and CPU busy release. Inspect S_R8/S_R16L/S_R16H/S_RD transitions.
4. Worst legal pitch and active-voice load against real service budget. Count incomplete samples, late requests and starvation. Traverse real requests; cached work cannot stand in for load.
5. Data port 22d/22e ROM/reverb access and pointer wrap. Prove SRAM depth from physical address pins.
6. Timer 227 cadence and reset; document TIM's board NC status instead of wiring it to suppress warnings.
7. Fixed-point signedness/widths, tables, volume/pan, accumulator headroom, saturation/wrap, reverb and YM auxiliary mixing. Use full-scale, impulse, phase and exact digital evidence before changing analog filters.

Configured gain 1.99, VOLSHIFT=1 and RC values each need circuit/measurement evidence or explicit approximation status. Verify FM CENs, sound-bank PAL behavior, ROM address truncation and mailbox cadence. Pin immutable algorithm/table provenance and licenses. Listening preference is not a hardware filter specification.

Exit: deterministic audio/register evidence, bounded arbitration/cadence, analyzed arithmetic and physical-board sound verification.

### P07 — Remaining video pipeline

Retain the corrected background channel order. Exercise asymmetric foreground/background colors, palette ends, priorities, transparency, brightness, shadow and blanking. Document request-to-selection-to-palette-to-RGB/HB/VB latency and assert companion phase.

Objects: actual DMA counts, overlap/priority, flips, wrap and zoom under SDRAM contention. Track buffer validity, ownership and frame epoch independently. Stress maximum lists through the real scanner; initialize mirrored memories and invalidate caches. Reject late prior-frame completions and reclamation of displayed/in-flight buffers.

Tiles: actual RAM/layer/page/bank selection, scroll modes, packed-MSB layout, global flip and ROM-ready stalls. Compare the real jt05415x contract. A shared defect requires authorized shared repair or a justified isolated wrapper, not a copied replacement architecture.

Exit: targeted and complete raw-frame comparisons pass, changed latencies/deadlines are covered, and no unexplained crop/offset/mask remains.

### P08 — Full scenario and platform matrix

Declare fixed input journals, checkpoints and native-frame stop barriers before execution.

| Scenario | Required evidence |
|---|---|
| moomesa, moomesauac, moomesauab, moomesaaab | ROM/MRA identity, boot and attract; per-set triage |
| Primary gameplay journal | Supported players' coin/start, movement/actions, transitions, object/audio load |
| Service/test | Entry, controls, device tests, exit and persistence |
| Reset matrix | Cold, soft, reload, service and active DMA/audio reset; retained/cleared state |
| Long run | Explicit native-frame count, no deadline/starvation failures, stable cadence |
| Scene mode | Combined NOMAIN/NOSOUND and repeated first stable frame |
| Debug/release MiSTer | Actual closure/observability differences and physical verification |

Choose concrete counts from reachable milestones; host elapsed seconds do not define a deterministic scenario. Require a clean cold-start replay after functional changes; checkpoints supplement it.

MiST/SiDi are explicitly skipped for BRAM budget. Pocket/other targets need separate interface/resource/build/smoke dispositions, or explicit unsupported configuration/documentation. MiSTer passing does not prove other targets.

## 6. P09 — Quartus and MiSTer acceptance

Read the current `mister-rbf-build` skill before executing. Quartus 17.0.2 is at D:/Q17. Use the approved global runner/slots, isolated project-local outputs and unchanged vendored IP. No raw Quartus bypass.

### Resolve actual runner capability gaps

Inspected capabilities were `workflowLease=false`, `unregisteredProcessAdmission=false`, `inferenceAudit=false`, `timingAudit=false`, `authenticatedAcceptance=false`, `seedSweep=false`, with single-stage slot lifetime. Map is available, complete acceptance is not. Reinspect because tooling may change.

If still absent, implement a genuinely compatible core-owned adapter/audit path satisfying the global contract, or obtain scoped authority for a shared-tool upgrade. Do not invent flags, wrap a PASS string, call artifact inventory acceptance or bypass process ownership. Local diagnostics can continue; final acceptance cannot be claimed through this gap.

### Build gates

1. Verify exact QPF/QSF/QIP closure, device, clocks, compressed settings, local output paths and framework/vendor hashes. Do not invent clock exceptions.
2. Fresh map and InferenceAudit: actual inferred memories/per-entity resources, latches, active undriven ports, multiplier widths and narrow warning dispositions. Reconcile intermediate messages with final reports.
3. Fit/STA across all corners: setup/hold WNS/TNS, recovery/removal/pulse width, important unconstrained endpoints, actual launch/capture paths and SDC collection expansion. Zero or unexpectedly broad matches fail.
4. Fix one causal timing problem at a time; rerun focused/cold functional checks after behavioral changes. Seed exploration follows structural correctness, then persist the best passing seed and clean-build unchanged inputs.
5. Require setup/hold WNS >= 0, TNS = 0, no unexplained relevant failures, fit and fresh compressed RBF. Positive margin is a separate preference. Check `Generate compressed bitstreams: On`; the unrelated assembler `Compression mode: Off` field alone is not a defect.
6. Bind reports, source/options, functional receipts and RBF hash to authentic machine-enforced acceptance. Keep build, staging, deployment and hardware statuses separate.

### MiSTer at 192.168.0.69

- Discover compatible tools and read system information first. Confirm returned host identity; do not guess credentials or claim access from the address alone.
- Preserve current known-good RBF/rollback. Put target/profile metadata in a core-owned `.mister/rbf-build.json` only after checking the actual schema.
- Stage only intended artifacts, verify remote hashes and preserve unrelated settings/ROMs/cores. Diagnostic candidates remain distinct from accepted releases.
- Confirm configuration and stable HDMI/display. On failure, inspect Main logs, compression and artifact identity before speculative RTL edits.
- Exercise sound, inputs, service, EEPROM save/reload, transitions and resets. A remote screenshot proves captured pixels only; physical audio/display/input claims need actual observation/capture.
- Clock/reset/video/pin changes need hardware confirmation before shipping. If inaccessible, record the missing check and retain the known-good artifact.

Exit: one accepted build hash tested on real hardware with rollback retained. Copy/load success is not gameplay validation.

## 7. P10 — Clean code and release documentation

Perform cleanup after functional gates, in small separately verifiable changes:

- Audit every port consumer; distinguish board NC/vendor diagnostics from accidental undriven functional signals. Never silence warnings with hardware changes unrelated to a proven defect.
- Remove proven dead functions/dependencies. Do not restore duplicate register mirrors to satisfy stale tests.
- Match JTCORES CPU organization where useful: declarations, explicit defaulted decoder, input mux, state, CPU last. Avoid restructuring during behavioral diagnosis.
- Prefer clear names, explicit widths/lanes and concise expert comments. Preserve licenses, provenance and evidence-critical caveats; comment density is not a deletion quota.
- Pin imported/adapted sources, immutable revisions and notices. Local MAME excerpts without version provenance remain open.
- Keep README feature/PCB-evidence/games/hardware/credits/license/install sections accurate. Board documentation is not proof the implementation passed hardware tests.
- Regenerate all four MRAs; validate headers, ROM ordering, rbf basename, rotation, resolution and boolean conventions. Resolve reference metadata; explicitly triage excluded Bucky/bootlegs.
- Publish only when requested. Verify the intended JTCORES distribution location, all curated MRAs, newest accepted compressed RBF and identical hashes across published copies. Do not force a standalone layout onto this core.

Exit: no collateral changes, generated-source edits, provenance loss, stale documentation or untested feature claims. Unchecked tasks are not completion.

## 8. Contracts and evidence records

Maintain contracts in the existing doc tree, for example `doc/contracts.md`, rather than several overlapping plans. Required rows: hardware/evidence inventory; decode/aliases; byte lanes; clocks/CEN including PCM gate; reset/retention; actual CDC protocols; ROM download/checksums; native raster; video/audio latency; fixed-point headroom; platform/resources; workarounds; scope/change ledger. Update affected rows before accepting each change.

Each iteration records:

```text
Packet / scenario / date:
Allowed files / actual diff:
Source, tools, reference, ROM/config and comparator digests:
Observation / evidence classification:
Competing hypotheses / falsification:
First producer / smallest change:
Before: domain, ordinal/frame, fields, prefix, digest:
After: old fingerprint absent, no earlier mismatch, advanced prefix/stop:
Focused / complete / prior regressions and actual exit statuses:
Map / inference / fit / timing / RBF / hardware dispositions:
Widths, lanes, state, latency, CEN/reset/CDC/SDC changes:
Known unknowns / exact next experiment:
```

One active mismatch per scenario. Preserve immutable goldens and rejected experiments. Never pass by masking, relaxed tolerance, reordered evidence, changed inputs, disabled assertions or weaker X handling.

## 9. Existing command entry points

Run from D:/jt; inspect current scripts and MCP schemas first. These small non-video tests already exist:

```powershell
python cores/moo/ver/audit/test_scripts.py
python cores/moo/ver/audit/test_scene.py
```

`prepare_map.py` writes generated production inputs under Moo, using native JTFRAME. Read it before running:

```powershell
python cores/moo/ver/audit/prepare_map.py
& 'C:/Program Files/PowerShell/7/pwsh.exe' -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -File 'C:/Users/meath/.codex/skills/mister-rbf-build/scripts/quartus_flow.ps1' -Action Capabilities
& 'C:/Program Files/PowerShell/7/pwsh.exe' -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -File 'C:/Users/meath/.codex/skills/mister-rbf-build/scripts/quartus_flow.ps1' -Action Slots
```

After capability/slot checks, the exercised map entry point is:

```powershell
& 'C:/Program Files/PowerShell/7/pwsh.exe' -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -File 'C:/Users/meath/.codex/skills/mister-rbf-build/scripts/quartus_flow.ps1' -Action Start -Stage map -ProjectRoot 'D:/jt/cores/moo/ver/audit/results/production' -Project jtmoo -Revision jtmoo
```

Start is asynchronous. Preserve its identity, poll that exact run using the current schema, inspect result.json and reports. Queued/started is not passed. Route large output through Context Mode.

For module Verilator tests, reuse the saved receipts' source/flag recipe with fresh workspace/output destinations. Discover and inspect `verilator_preflight`, `verilator_workspace`, `verilator_project_run`. Simulation invokes the safe simulator with the R:-resident model as its first argument. Preserve headless=true, displayBackend=none, runtimeThreads=1. Never execute stale models directly or copy them to evade launchers.

Previously exercised MRA entry point: `jtframe mra moo --git --skipROM --skipPocket`, with output environment inside Moo. Inspect `validate_mra.py` arguments before invoking. This does not assemble private ROMs or establish reference-version agreement.

## 10. Handoff and final review

At handoff record last completed packet, exact candidate, one next command/experiment and any external evidence gap. Do not restart the audit or repeatedly rewrite the plan instead of executing the first open task.

Before claiming completion answer: physical fact/evidence for each change; first causal divergence and prefix advancement; widths/state/latency; CEN/reset/CDC proof; actual SDC endpoints or none changed; aliases/lanes/ROM/raster/audio exercised; removed workarounds; tested/skipped sets/platforms; collateral/generated/provenance audit; remaining unknowns and why they do not invalidate the claimed gate.

**Next action: finish P00 generation reproducibility, then P01's untested K054338 scene loader and integrated scene round trip.** Source visibility is repaired; see [completion-progress.md](completion-progress.md). No final RBF was built while preparing this plan or in the recorded P00 execution.
