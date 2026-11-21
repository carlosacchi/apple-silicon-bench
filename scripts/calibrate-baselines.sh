#!/bin/bash
set -euo pipefail

# Recalibrates BenchmarkScorer.referenceValues on the baseline M1 (MacBook Air, 8 GB).
# Runs N full-mode passes with a cooldown between them and prints the median of every test.
#
# Usage: ./scripts/calibrate-baselines.sh [passes] [only]
#   ./scripts/calibrate-baselines.sh                 # 5 passes of cpu-single,gpu
#   ./scripts/calibrate-baselines.sh 5 memory        # 5 passes of the memory tests
#   COOLDOWN=120 ./scripts/calibrate-baselines.sh    # longer cooldown (fanless Macs)
#
# Before running: power connected, Low Power Mode off, other apps closed (browsers and
# editors make CPU and GPU results 5-10% lower). Each pass also saves the usual HTML report
# to ~/Desktop/OSX-Bench-Reports.

PASSES="${1:-5}"
ONLY="${2:-cpu-single,gpu}"
COOLDOWN="${COOLDOWN:-60}"
BIN="${BIN:-.build/release/osx-bench}"
OUT="$(mktemp -d -t osx-bench-calibration)"

if [ ! -x "$BIN" ]; then
    echo "Build first: swift build -c release (or set BIN=path/to/osx-bench)"
    exit 1
fi

for i in $(seq 1 "$PASSES"); do
    echo "Pass $i of $PASSES ($ONLY)..."
    "$BIN" run --only "$ONLY" --autoaccept --export "$OUT/pass-$i.json" > "$OUT/pass-$i.log"
    if [ "$i" -lt "$PASSES" ]; then
        sleep "$COOLDOWN"
    fi
done

python3 -I - "$OUT"/pass-*.json <<'EOF'
import json
import statistics
import sys

values = {}
for path in sys.argv[1:]:
    with open(path) as f:
        data = json.load(f)
    for bench in data["results"]["benchmarks"]:
        for test in bench["tests"]:
            if test.get("skipReason"):
                continue
            key = (bench["type"], test["name"], test["unit"], test.get("informational", False))
            values.setdefault(key, []).append(test["value"])

for (kind, name, unit, info), vals in values.items():
    spread = (max(vals) - min(vals)) / statistics.median(vals) * 100
    tag = "  (info)" if info else ""
    print(f"{kind:10} {name:26} median {statistics.median(vals):10.2f} {unit:9} "
          f"min {min(vals):.2f}  max {max(vals):.2f}  spread {spread:.1f}%  n={len(vals)}{tag}")
EOF

echo "JSON exports and logs: $OUT"
