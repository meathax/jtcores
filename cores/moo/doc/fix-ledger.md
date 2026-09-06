# Audit correction ledger

Write scope: `cores/moo` only. Starting repository identity:
`8248dc6c3414dcd251be2778f80c82da78103acf`, with the pre-existing shared
Simpsons object and JT05415x edits recorded in `audit.md`.

## Production synthesis preparation

Observation: this checkout has no Moo production QPF/QSF.
Evidence: the JTFRAME `jtcore`/`jtcore-funcs` flow generates the MiSTer
templates, memory integration, file list, OSD ROM and credits locally.
Hypotheses: absent generated project versus a native generator failure.
Selected explanation: both are present; the first attempted map confirmed
that native QIP backslashes are interpreted as Tcl escapes. The next attempt
reached HPS elaboration and identified the missing `cfgstr.hex` generation.
Smallest change: `ver/audit/prepare_map.py` generates inputs beneath its
ignored results directory, converts QIP separators and removes exact duplicate
assignments without reordering their first occurrence. Shared RTL is read-only.
Verification: real `sys_top`, Quartus 17.0.2 Build 602 through the global runner.
Regression scope: MiSTer only, not Fit/STA or release acceptance.
Known unknowns: generator source order remains noncanonical; each generated
closure must be hashed. This script does not regenerate MMR source or attest
an RBF build. Its QSF references the original, unmodified vendor framework.

## AUD-03: absent-CPU bus contract

Observation: NOMAIN references undeclared `reg_cs` and leaves outputs undriven.
Evidence: original compiler receipt in `ver/audit/results/nomain`; exact
declaration and excluded branch in `hdl/jtmoo_main.v`.
Hypotheses: missing declaration versus stale inactive-CPU branch. The normal
decoder owns `reg_cs`; the inactive branch must not decode CPU transactions.
Selected explanation: stale branch with no complete idle-bus contract (KNOWN).
Smallest change: remove unused saved-state placeholders and illegal assignment;
drive scroll/CCU selects and RAM/object write strobes inactive, R/W high and
both active-low data strobes high. Production branch is unchanged. No clock,
reset, memory width, latency, SDC or hardware device behavior changes.
Verification: `tb_nomain.sv` asserts every output, no transaction, and idle
active-low strobes across 48 clock cycles and reset transitions. Strict flags
retain timing, unique X, assertions, Wall and one runtime thread. The only
focused waivers are the 27 specifically named CPU inputs intentionally unused
by NOMAIN and this module's absent timescale (the timed bench owns time).
No undriven, width, latch, loop or other functional diagnostic is waived.
Regression scope: isolated NOMAIN module passes; combined scene hierarchy,
NOSOUND and real captured-state round trip remain separate pending gates.
Known unknowns: the old placeholder never restored state. Removing it does
not repair or certify AUD-04.

Receipts: `ver/audit/results/fixes/nomain-build2/receipt.json` and
`nomain-run2/receipt.json`; finalized marker at 480 ns. MCP rejected direct
R:-executable dispatch; the supported `verilator-sim-safe.exe` path was used.

The production branch is byte-identical to the original after line-ending
normalization. A second reset/X-seed run (17) passes the same assertions.
Production map `20260905-130235-210-map` passes with 0 errors and 16,906
warnings. This establishes synthesis, not clean lint, fit or timing.

## AUD-02: background channel boundary

Observation: the rebuilt pre-edit test produces RGB `553311` instead of
`113355` for background register value `123456` at brightness 255.
Evidence: `jt054338.v` assigns background in RGB order; `jtmoo_colmix.v`
stores BGR and all palette branches explicitly assemble that order.
The retained `doc/k054338.cpp` register descriptions agree on R/G/B ordering.
Hypotheses: global output swap versus background-only packing. The palette
branch already has the correct order, selecting the background boundary.
Selected explanation: a byte-order mismatch at the first consumer (KNOWN).
Smallest change: permute the background bytes at the mux input. No widths,
signedness, arithmetic, registers, clocks, resets, CDC, latency, SDC, memory
aliases, ROM layout, raster timing or gain changed. No offset/crop workaround.
Verification: `colmix_test.cpp`, real maintained mixer/chip/priority/RAM
modules. Before: first asymmetric background fails. After: five background
colors, foreground palette bypass, both blanking signals and video disable
pass from cold reset with unique-X seeds 1 and 17. Same test, same input
sequence, no tolerance changes. Compile/link/runtime faults encountered while
constructing the harness are preserved and excluded from RTL evidence.
Regression scope: affected local background branch and unchanged palette/
blanking paths; production MiSTer map required. No sibling RTL changed.
Known unknowns: this is a focused functional correction, not silicon brightness
verification, MAME lockstep, all blending/shadow modes or hardware acceptance.
Real-MiSTer display verification is pending; do not ship this edit as a verified
release until that gate passes, and revert it from a release candidate if
hardware verification cannot be performed.

### Focused diagnostic warning disposition

`colmix_diagnostic.vlt` and `nomain_diagnostic.vlt` preserve the exact
file/line or input-name scope used for these diagnostic tests. They are not
release warning allowlists. The mixer inventory has 82 messages: explicit
unconnected chip/mirror outputs; intentionally discarded color/arithmetic
bits; inactive shared RAM simulation parameters/state; generated MMR debug
address bits; one donor filename/EOF convention; and mixed synchronous and
asynchronous reset consumers. No width, latch or combinational-loop warning
was waived. The unused priority-control outputs remain an architecture-review
question; these tests do not certify them as harmless hardware omissions.

### MRA and reference checks

Native `jtframe mra moo --git --skipROM --skipPocket`, with JTBIN inside the
ignored core results directory, generates all four expected sets. The new
`validate_mra.py` reparses XML and checks set completeness, RBF basename,
rotation, version consistency and optional convention fields. All four pass
and identify database version 0282. No ROM was assembled or distributed.

MAME MCP config reports version 0.289, executable SHA-256
`af6966108d9b52c22465c6d50f4e5d50cc371b50f2d27dc443935f287aad37a3`.
The default ROM audit failed because no path was configured. A read-only
search found existing private archives; a second audit of moomesa succeeds.
This corrects the path problem, not the source/database identity gap.

All three clone archives also pass MAME's read-only ROM audit. These audits
are media checks, not emulator executions or paired frame evidence.

## Final gate disposition

Post-background-fix production map `20260905-131105-819-map` completed with
exit 0, 0 errors and 16,903 warnings. Resource estimates are unchanged:
54,246 logic cells, 1,617 RAM segments, 65 DSP elements and 3 PLLs.
The final per-entity rows implement the shared object even/odd RAMs as RAM
(16,384 bits each, zero logic/registers). Intermediate uninferred messages
alone did **not** prove a logic implementation; the initial suspicion is
withdrawn. No shared RAM correction is justified by these results.

The installed global runner's actual `Capabilities` response states:

```json
{
  "workflowLease": false,
  "unregisteredProcessAdmission": false,
  "inferenceAudit": false,
  "timingAudit": false,
  "authenticatedAcceptance": false,
  "seedSweep": false
}
```

This check was performed late, after map; that sequencing is an evidence
limitation. The map receipts are compiler evidence only and cannot satisfy
the mandated machine-enforced inference/acceptance contract. No acceptance
certificate or release verdict is claimed. Repairing the global runner would
violate this task's Moo-only write scope. Do not substitute a local fabricated
PASS certificate or direct compiler launch.

| Finding | Status and next closure evidence |
|---|---|
| AUD-01 | Open: prove the coordinate line/frame origin and edge phase with the real CCU and board/reference contract before changing the counter |
| AUD-02 | Corrected; focused seeds and production map pass; full mixer/game and real-MiSTer acceptance remain open |
| AUD-03 | Isolated NOMAIN bus fixed and tested; combined scene restoration is still open |
| AUD-04 | Open: core-owned serialized schema and complete captured-state round trip, including register banks and upper palette/object halves |
| AUD-05 | Open: define a debug selector preserving access to both palette register banks, then test real consumers |
| AUD-06 | Open: establish one reproducible PCM fault or prove bounded scheduling/handshake/format/reset tests before changing hardware |
| AUD-07 | Native production input preparation works; global generator ordering and complete acceptance tooling remain open |
| AUD-08 | Four-set MRA generation/validation and ROM availability checked; immutable imported-source and reference-version agreement remain open |
| AUD-09 | No speculative cosmetic RTL cleanup or notice removal; low-priority candidates remain as recorded in the audit |

The global tooling blocker prevents claiming the requested complete closure.
It does not turn unimplemented local work into a completed item. No final RBF,
Fit, STA, deployment, live MAME/Verilator comparison or hardware test was run.

### Self-review

1. Changed hardware behavior is only RGB-to-BGR background packing, supported
   by its actual producer/consumer and retained K054338 register reference.
2. The first incorrect byte boundary is repaired; no crop, delay or mask added.
3. No production width, signedness, truncation, state or latency changed.
4. No production clock, CEN, reset or CDC path changed; NOMAIN reset/idle
   outputs pass both X seeds.
5. No SDC endpoint/exception or pin assignment changed.
6. Tests exercise asymmetric colors, xRGB palette word writes, blanking and
   video disable. Full download, aliases, raster and audio contracts remain open.
7. Only stale inactive-CPU placeholders were removed; no functional workaround
   was declared obsolete without evidence.
8. MiSTer map passed; four MRA/ROM audits passed. No other platform or sibling
   simulation was accepted; shared RTL bytes remain outside the edit scope.
9. The final scope/hash check distinguishes pre-existing shared changes from
   this task. Generated build outputs are ignored, not hand-maintained RTL.
10. Full hardware/accuracy/tooling gates remain explicit. The result is a
    tested partial correction, not completion of the user's all-blockers goal.
