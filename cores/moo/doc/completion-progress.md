# Completion execution — 2026-09-05

Goal remains active. No packet or hardware acceptance is claimed by this record.

## P00: source visibility repaired; generation reproducibility open

Allowed and changed paths: `cores/moo/.gitignore`,
`ver/audit/prepare_map.py`, `ver/audit/check_generation.py`,
`ver/audit/test_generation.py`, this record, and the plan status pointer.
Evidence is under `ver/audit/results/p00/`. No shared file was edited.

Observation: Git's root `*_dump.v` rule hid the serializer. The preparation
adapter had one fixed output directory. Two independent generations differ.

Evidence (KNOWN): all source hashes in `plan-baseline.md` matched before work.
`git check-ignore -v` identified root `.gitignore:92`. After a core-local
exception, status reports `?? cores/moo/hdl/jtmoo_dump.v`.
Both `prepare_map.py --output .../generation-a` and `generation-b` exited 0.
`closure-comparison.json` records their hashes, direct ordered QIP entries,
equal membership, unequal order, and four differing generated files.

Competing hypotheses and falsification: output-directory spelling explains
only the generated wrapper path; the comparator relocates that path and still
fails. Actual source ordering, EEPROM port ordering and timestamp differ.
`modules/jtframe/src/jtframe/files/files.go:140` iterates the alias map;
`mem/mem.go`'s `fill_implicit_ports` appends ports from a map;
`macros/macros.go:336` obtains `JTFRAME_TIMESTAMP` from `time.Now().Unix()`.
This is direct local source evidence, not upstream-maintainer advice.

Smallest completed change: expose the serializer and add a core-contained
output-directory argument. Add a fail-closed comparison diagnostic; preserve
source order and macro values rather than sorting or suppressing differences.
The checker deliberately covers direct QIP entries and generated files only;
it does not claim recursive Tcl closure or elaborated-hierarchy equivalence.

Verification: 12 shell-adapter, 3 scene-parser and 5 generation-checker tests
passed (20 total). Negative cases reject reordered sources, missing sources,
added macro files and unparsed QIP commands. The real comparison exits 1 as
expected, with `source_membership_equal=true`, `source_order_equal=false`.
All eleven Moo entries appear; neither stale K053251/K054338 mirror appears.
The final `git diff --check -- cores/moo` exits 2 for the pre-existing blank
line at EOF in `cfg/mmr.yaml`; its baseline hash matched and it was not edited.
Full outputs: `python-tests.json`, `generation-a.log`, `generation-b.log`,
`generation-comparison.json`, `closure-comparison.json`.

Shared-lesson use: generated top fan-out/source closure must be checked before
trusting build success; therefore the first experiment compared actual emitted
inputs instead of rerunning synthesis against an assumed unchanged project.

MCP: Verilator preflight passed and reported forced runtime thread count 1,
headless operation, no display backend and R:-resident model storage. No model
was built or simulated. No MAME comparison, Quartus stage, RBF, deployment or
hardware verification ran during this execution segment.

Hardware self-review: no hardware block, arithmetic width, state, latency,
CEN/reset/CDC, SDC endpoint, ROM lane or raster behavior changed. Existing
shared modifications remain preserved. No old receipts were promoted to new
functional acceptance. Source visibility changes no synthesizable semantics.

Next experiment: establish an order-preserving core-owned generation strategy
for the proven Go-map nondeterminism, pin the build timestamp explicitly, and
repeat independent generation. Do not sort arbitrary HDL or edit shared tools.
Prove named-port-only normalization before adopting it; validate package and
preprocessor ordering and recursive QIP inputs. Audit dead `jt539` separately.
Then finish P00 and proceed to P01's strict K054338 file-size/restore baseline.
The K054338 loader still has the plan's untested trailing-byte risk.
