#! /bin/bash -eu
set -o pipefail

# Compare peak memory (Maximum resident set size) and wall-clock time of
# javacgflow_old.pl (native recursion) vs javacgflow.pl (explicit
# stack) on synthetic linear-chain call graphs of increasing depth.
#
# Usage:
#   benches/run_benchmark.sh [DEPTH...]
#   benches/run_benchmark.sh 100 1000 5000 10000 20000 50000
#
# With no arguments, a default set of depths is used.
#
# Requires GNU time (/usr/bin/time -v). Prints a CSV summary to stdout;
# the raw `time -v` output and each script's own stderr are kept under
# benches/out/ for inspection, one pair of files per (variant, depth).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEN="$ROOT_DIR/benches/generate_call_graph.pl"
OUT_DIR="$ROOT_DIR/benches/out"
mkdir -p "$OUT_DIR"

if ! command -v /usr/bin/time >/dev/null 2>&1; then
    echo "error: /usr/bin/time (GNU time) is required but was not found" >&2
    exit 1
fi

DEPTHS=("$@")
if [ ${#DEPTHS[@]} -eq 0 ]; then
    DEPTHS=(100 1000 5000 10000 20000 50000)
fi

# Run one script against one data file, and print one CSV row summarizing
# its peak memory and elapsed time.
measure() {
    local script="$1" depth="$2" data_file="$3" variant="$4"
    local time_log="$OUT_DIR/${variant}_${depth}.time.log"
    local stderr_log="$OUT_DIR/${variant}_${depth}.stderr.log"
    local status=0

    /usr/bin/time -v -o "$time_log" "$script" "$data_file" \
        >/dev/null 2>"$stderr_log" || status=$?

    local rss elapsed note
    rss=$(grep 'Maximum resident set size' "$time_log" 2>/dev/null \
        | awk -F': ' '{print $2}')
    elapsed=$(grep 'Elapsed (wall clock) time' "$time_log" 2>/dev/null \
        | awk -F': ' '{print $2}')
    note=""
    if [ "$status" -ne 0 ]; then
        if [ "$status" -eq 139 ]; then
            note="segfault (likely C stack overflow)"
        else
            note="exit=$status; see $stderr_log"
        fi
    fi

    echo "${depth},${variant},${status},${rss:-NA},${elapsed:-NA},${note}"
}

echo "depth,variant,exit_status,max_rss_kb,elapsed_time,note"

for depth in "${DEPTHS[@]}"; do
    data_file="$OUT_DIR/chain_${depth}.javacg-static"
    "$GEN" -s chain -d "$depth" >"$data_file"

    measure "$ROOT_DIR/javacgflow_old.pl" "$depth" "$data_file" "old"
    measure "$ROOT_DIR/javacgflow.pl" "$depth" "$data_file" "new"
done
