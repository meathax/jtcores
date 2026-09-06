"""Compare two generated Moo projects without hiding source-order differences."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re

MOO_SOURCES = {
    "jt054338.v", "jtk053252_mmr.v", "jtmoo_colmix.v", "jtmoo_dump.v",
    "jtmoo_game.v", "jtmoo_k054539.v", "jtmoo_main.v", "jtmoo_prot.v",
    "jtmoo_scroll.v", "jtmoo_sound.v", "jtmoo_video.v",
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def inventory(root):
    result = {}
    for path in sorted(root.iterdir()):
        if path.is_file():
            raw = path.read_bytes()
            # Only relocate the output directory; do not sort HDL or erase macros.
            normalized = raw.replace(str(root).encode(), b"<OUTPUT>")
            normalized = normalized.replace(root.as_posix().encode(), b"<OUTPUT>")
            result[path.name] = {"sha256": digest(raw),
                                 "relocated_sha256": digest(normalized)}
    return result


def sources(root):
    entries = []
    for line in (root / "files.qip").read_text().splitlines():
        match = re.fullmatch(r"set_global_assignment -name (\w+_FILE) (.+)", line)
        if not match:
            raise ValueError(f"Unparsed source assignment: {line!r}")
        kind, name = match.groups()
        path = Path(name)
        if not path.is_file():
            raise ValueError(f"Missing source: {path}")
        label = path.as_posix().replace(root.as_posix(), "<OUTPUT>")
        entries.append({"kind": kind, "path": label,
                        "sha256": digest(path.read_bytes())})
    return entries


def compare(left, right):
    a, b = inventory(left), inventory(right)
    sa, sb = sources(left), sources(right)
    changed = [name for name in sorted(a.keys() | b.keys())
               if a.get(name, {}).get("relocated_sha256") !=
               b.get(name, {}).get("relocated_sha256")]
    ka = [(s["kind"], s["path"]) for s in sa]
    kb = [(s["kind"], s["path"]) for s in sb]
    moo = [Path(s["path"]).name for s in sa
           if "/cores/moo/hdl/" in s["path"]]
    stale = sorted(set(moo) & {"jtk053251_mmr.v", "jtk054338_mmr.v"})
    return {"schema": "moo-generation-comparison-v1",
            "scope": "top-level generated files and direct QIP assignments; not elaboration",
            "left": str(left), "right": str(right),
            "files_left": a, "files_right": b,
            "sources_left": sa, "sources_right": sb,
            "changed_files": changed, "source_order_equal": ka == kb,
            "source_membership_equal": Counter(ka) == Counter(kb),
            "moo_entries": moo, "stale_register_mirrors": stale,
            "pass": not changed and ka == kb and not stale and
                    set(moo) == MOO_SOURCES and len(moo) == len(MOO_SOURCES)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("left", type=Path)
    parser.add_argument("right", type=Path)
    parser.add_argument("--receipt", required=True, type=Path)
    args = parser.parse_args()
    result = compare(args.left.resolve(), args.right.resolve())
    args.receipt.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.receipt.with_suffix(".tmp")
    temporary.write_text(json.dumps(result, indent=2) + "\n")
    temporary.replace(args.receipt)
    print(json.dumps({key: result[key] for key in
                      ("pass", "changed_files", "source_order_equal",
                       "source_membership_equal", "moo_entries",
                       "stale_register_mirrors")}, indent=2))
    return 0 if result["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
