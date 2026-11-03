#!/usr/bin/env python3
"""Every accessibility identifier in Discipline's screens (App/Sources, the debug Element Gallery excluded) and whether a
UI test drives or checks it. Saidie, Nov 3 2026: "go through every action, every button, and make sure everything works".
Prints one line per identifier: covered / NOT COVERED. Exit 0 always (a report, not a gate)."""
import pathlib, re
ROOT = pathlib.Path(__file__).resolve().parent.parent
ids = set()
for f in (ROOT / "App" / "Sources").rglob("*.swift"):
    if f.name == "ElementGallery.swift":
        continue
    ids |= set(re.findall(r'accessibilityIdentifier\("([^"]+)"\)', f.read_text(encoding="utf-8")))
tests = "\n".join(f.read_text(encoding="utf-8") for f in (ROOT / "UITests").glob("*.swift"))
miss = 0
for i in sorted(ids):
    base = i.split("\\(")[0]
    ok = base in tests
    miss += not ok
    print(("covered      " if ok else "NOT COVERED  ") + i)
print(f"\n{len(ids) - miss} of {len(ids)} identifiers are driven or checked by a UI test")
