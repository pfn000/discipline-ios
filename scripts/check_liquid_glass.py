#!/usr/bin/env python3
"""Liquid Glass guard for Discipline (Saidie, Oct 21 + Oct 26 2026: the app must use Apple's real Liquid Glass).

Fails the build when app code imitates glass instead of using the native iOS 26+ APIs
(glassEffect, GlassEffectContainer, .buttonStyle(.glass / .glassProminent), the system TabView and toolbars).
Prints a per-file count of the native glass APIs it found.
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "App" / "Sources"

FORBIDDEN = [
    (r"\b(ultraThin|thin|regular|thick|ultraThick|bar)Material\b", "SwiftUI Material blur used as fake glass"),
    (r"\bMaterial\s*\.", "SwiftUI Material used as fake glass"),
    (r"\.blur\s*\(", ".blur() used to fake a glass look"),
    (r"\bUIVisualEffectView\b|\bUIBlurEffect\b", "UIKit blur view used as fake glass"),
    (r"\.buttonStyle\(\s*\.(bordered|borderedProminent|borderless)\s*\)", "pre-Liquid-Glass button style; use .glass or .glassProminent"),
    (r"\.toolbarBackground\s*\(", "custom toolbar background hides the system Liquid Glass bar"),
    (r"\.toolbarBackgroundVisibility\s*\(", "custom toolbar background hides the system Liquid Glass bar"),
]
PLAIN = re.compile(r"\.buttonStyle\(\s*\.plain\s*\)")
NATIVE = re.compile(r"\.glassEffect\s*\(|GlassEffectContainer|\.buttonStyle\(\s*\.glass(Prominent)?\s*\)|\.glassEffectID\s*\(|\.glassEffectUnion\s*\(")

def main() -> int:
    problems, counts = [], {}
    files = sorted(SRC.rglob("*.swift"))
    for f in files:
        lines = f.read_text(encoding="utf-8").splitlines()
        rel = f.relative_to(ROOT)
        counts[str(rel)] = sum(len(NATIVE.findall(l)) for l in lines)
        for n, line in enumerate(lines, 1):
            code = line.split("//", 1)[0]
            for pat, why in FORBIDDEN:
                if re.search(pat, code):
                    problems.append(f"{rel}:{n}: {why}: {line.strip()}")
            if PLAIN.search(code):
                prev = lines[n - 2] if n > 1 else ""
                if "glass-ok:" not in line and "glass-ok:" not in prev:
                    problems.append(f"{rel}:{n}: .plain button without a 'glass-ok:' note saying its label is native glass")
    root = (SRC / "DisciplineApp.swift").read_text(encoding="utf-8")
    if not re.search(r"\bTabView\b", root) or not re.search(r"\bTab\(", root):
        problems.append("App/Sources/DisciplineApp.swift: the root must be the system TabView with Tab(...) items (native Liquid Glass tab bar)")
    total = sum(counts.values())
    print("native Liquid Glass API uses per file:")
    for k, v in counts.items():
        print(f"  {v:3d}  {k}")
    print(f"  {total:3d}  total")
    if total == 0:
        problems.append("no native Liquid Glass API found at all")
    if problems:
        print("\nLIQUID GLASS CHECK FAILED:")
        for p in problems:
            print("  " + p)
        return 1
    print("\nLiquid Glass check passed: no fake-glass materials, blurs or pre-glass button styles.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
