#!/bin/bash
# Ouija palette lint (Saidie, Nov 1 2026: "that purple too often").
# Fails on any purple/violet/indigo, any named system colour other than green (yes) and red (no) via OuijaStyle,
# any hand-made colour, or any hex value in Ouija's code. All colours live in Shared/OuijaStyle.swift.
cd "$(dirname "$0")/.."
PAT='purple|violet|indigo|magenta|lavender|\.(orange|blue|pink|yellow|mint|teal|cyan|green|red|brown)\b|Color\.(red|green|blue|orange|yellow)\b|Color\(red:|Color\(hue|UIColor\(red|#[0-9A-Fa-f]{6}\b|\.accentColor|Gradient'
bad=$(grep -rnE "$PAT" Ouija OuijaWidgets --include=*.swift | grep -v '^\s*//' | grep -vE '^[^:]+:[0-9]+:\s*///?')
# Style file: only it may build colours, and it may never mention purple/violet/indigo outside its own header.
sbad=$(grep -nEi 'purple|violet|indigo|magenta|lavender|#[0-9A-Fa-f]{6}\b' Shared/OuijaStyle.swift | grep -vE '^[0-9]+:\s*///?' )
if [ -n "$bad$sbad" ]; then echo "PALETTE LINT FAILED"; echo "$bad"; echo "$sbad"; exit 1; fi
echo "palette lint ok: no purple/violet/indigo, no stray colours in Ouija/ or OuijaWidgets/"
