#!/usr/bin/env bash

# Proves the training exporter is byte-stable across separate processes. Swift
# randomizes hash iteration per process, so one process writing twice would
# preserve the exact determinism bug this check exists to catch.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="$REPO_ROOT/Packages/CatanAI"
OUTPUT_DIR="$(mktemp -d)"
trap 'rm -rf "$OUTPUT_DIR"' EXIT

swift build --package-path "$PACKAGE" --product sim >/dev/null
SIM="$(swift build --package-path "$PACKAGE" --show-bin-path)/sim"

for run in first second; do
  "$SIM" --games 1 --seed 53191 --jsonl \
    --build-id training-export-smoke \
    --training-information reveal-all \
    --training-jsonl "$OUTPUT_DIR/$run.jsonl" \
    > "$OUTPUT_DIR/$run-games.jsonl"
done

cmp "$OUTPUT_DIR/first.jsonl" "$OUTPUT_DIR/second.jsonl"
python3 "$REPO_ROOT/scripts/validate-training-data.py" \
  --build-id training-export-smoke \
  --information-policy revealAll \
  "$OUTPUT_DIR/first.jsonl"
