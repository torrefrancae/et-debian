#!/usr/bin/env bash
# Tiny helper: briefly show a mouse highlight via xdotool (optional).
# Full Mac/Windows circle tools stay on the operator Mac under ~/proj/config.
set -euo pipefail
command -v xdotool >/dev/null || { echo "xdotool missing"; exit 1; }
# no-op pulse: move 0 — reserved for future OSD; keeps path stable for wrappers
xdotool getmouselocation --shell >/dev/null
echo "mouse-circle: location ok (install a real OSD later if needed)"
