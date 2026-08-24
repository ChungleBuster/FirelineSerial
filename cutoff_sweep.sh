#!/usr/bin/env bash
set -euo pipefail

# Sequential-cutoff sweep for the Fireline parallel assignment.
#
# For every (cutoff, n) combination this:
#   1. writes FireTask.SEQUENTIAL_CUTOFF = <cutoff> into FireTask.java,
#   2. recompiles with `make all`,
#   3. runs FirelineParallel once on an n x n grass/wildfire grid,
#   4. appends one CSV row to test_data/results.txt.
#
# Cutoffs tested: 1000, 5000, 10000, 50000, 100000
# Grid sizes tested (rows == columns): 100, 200, 300, 400, 500
#
# Every result row records every value needed to run the exact same
# scenario again by hand:
#   1. set FireTask.SEQUENTIAL_CUTOFF = <cutoff> in FireTask.java
#   2. cd src && make all
#   3. run the "command" column shown in that row
#
# FireTask.java is restored to its original contents (and recompiled) when
# this script finishes, whether it finishes normally or is interrupted.
#
# This script only WRITES results.txt; it does not analyse or plot it.
#
# This script lives inside FirelineSerial/ itself, so ROOT_DIR below IS the
# FirelineSerial directory (not its parent) — paths are relative to that.
#
# The department server this has been run on (nightmare) has been observed
# to intermittently kill javac/java processes outright (SIGTERM, i.e. make
# reports "Error 143") for reasons that don't trace back to ulimits, memory
# pressure, or disk quota — most likely transient load from many students
# running the same assignment at once. Both the compile step and each
# simulation run are therefore retried a few times with a short delay
# before being given up on, so one transient kill doesn't abort the whole
# sweep. Anything that still fails after MAX_ATTEMPTS is logged to stderr
# and skipped (no row written for it) rather than aborting the script.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$ROOT_DIR/src"
FIRETASK="$SRC_DIR/FireTask.java"
RESULTS_DIR="$ROOT_DIR/test_data"
RESULTS_FILE="$RESULTS_DIR/seq_results.txt"

CUTOFFS=(1000 10000 50000 75000 100000)
SIZES=(300 400 500 600 700)

SEED=42
MODE=wildfire
LANDSCAPE=grass
MAX_STEPS=50000
TOLERANCE=0.05

MAX_ATTEMPTS=4
RETRY_DELAY=5

log_retry() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*" >&2
}

# Retries `make all` up to MAX_ATTEMPTS times. Returns non-zero only after
# every attempt has failed.
compile_with_retry() {
    local attempt=1
    local errfile
    errfile="$(mktemp)"
    while true; do
        if ( cd "$SRC_DIR" && make all ) >/dev/null 2>"$errfile"; then
            rm -f "$errfile"
            return 0
        fi
        local status=$?
        if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
            log_retry "make all failed after $attempt attempt(s) (exit $status); giving up. Last error output:"
            cat "$errfile" >&2
            rm -f "$errfile"
            return "$status"
        fi
        log_retry "make all failed (exit $status), attempt $attempt/$MAX_ATTEMPTS — retrying in ${RETRY_DELAY}s"
        sleep "$RETRY_DELAY"
        attempt=$((attempt + 1))
    done
}

# Runs one simulation command (with retries) and prints its stdout once the
# output actually contains the "Core simulation time:" line — proof the run
# completed rather than being killed partway through. Returns non-zero only
# after every attempt has failed to produce complete output.
run_simulation_with_retry() {
    local cmd="$1"
    local attempt=1
    local out
    while true; do
        out="$( cd "$SRC_DIR" && eval "$cmd" )" || true
        if echo "$out" | grep -q '^Core simulation time:'; then
            printf '%s' "$out"
            return 0
        fi
        if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
            log_retry "Run produced incomplete output after $attempt attempt(s) — giving up: $cmd"
            return 1
        fi
        log_retry "Run produced incomplete output (likely killed mid-run), attempt $attempt/$MAX_ATTEMPTS — retrying in ${RETRY_DELAY}s: $cmd"
        sleep "$RETRY_DELAY"
        attempt=$((attempt + 1))
    done
}

if [ ! -f "$FIRETASK" ]; then
    echo "Cannot find $FIRETASK" >&2
    exit 1
fi
if ! grep -q 'static int SEQUENTIAL_CUTOFF = [0-9]*;' "$FIRETASK"; then
    echo "Could not find a 'static int SEQUENTIAL_CUTOFF = <number>;' line in $FIRETASK" >&2
    exit 1
fi

mkdir -p "$RESULTS_DIR"

cp "$FIRETASK" "$FIRETASK.orig"
cleanup() {
    if [ -f "$FIRETASK.orig" ]; then
        mv "$FIRETASK.orig" "$FIRETASK"
        ( cd "$SRC_DIR" && make all ) >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

{
    echo "# Cutoff sweep - $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "# Fixed simulation parameters: seed=$SEED mode=$MODE landscape=$LANDSCAPE max_steps=$MAX_STEPS tolerance=$TOLERANCE"
    echo "# To recreate any row by hand:"
    echo "#   1. set 'static int SEQUENTIAL_CUTOFF = <cutoff>;' in src/FireTask.java"
    echo "#   2. (cd src && make all)"
    echo "#   3. run the exact command in the 'command' column below (from src/)"
    echo "implementation,cutoff,rows,columns,seed,mode,landscape,max_steps,tolerance,timesteps,converged,burning_cells,cells_burned,max_peak_temperature,max_temperature_change,core_ms,command"
} >> "$RESULTS_FILE"

for cutoff in "${CUTOFFS[@]}"; do
    sed -i.tmp "s/static int SEQUENTIAL_CUTOFF = [0-9]*;/static int SEQUENTIAL_CUTOFF = ${cutoff};/" "$FIRETASK"
    rm -f "$FIRETASK.tmp"

    if ! compile_with_retry; then
        log_retry "Skipping cutoff=$cutoff entirely — compilation failed after $MAX_ATTEMPTS attempt(s)."
        continue
    fi

    for n in "${SIZES[@]}"; do
        prefix="output/cutoff_${cutoff}_${n}x${n}"
        cmd="java -cp bin FirelineParallel $n $n $SEED $MODE $prefix $MAX_STEPS $TOLERANCE $LANDSCAPE"

        if ! out="$(run_simulation_with_retry "$cmd")"; then
            log_retry "Skipping cutoff=$cutoff n=$n — no row written."
            continue
        fi

        timesteps=$(echo "$out"   | grep '^Timesteps completed:'              | awk '{print $3}')
        converged=$(echo "$out"   | grep '^Converged:'                        | awk '{print $2}')
        burning=$(echo "$out"     | grep '^Final burning cells:'              | awk '{print $4}')
        burned=$(echo "$out"      | grep '^Cells burned:'                     | awk '{print $3}')
        peak=$(echo "$out"        | grep '^Maximum peak temperature:'         | awk '{print $4}')
        maxchange=$(echo "$out"   | grep '^Maximum change in final timestep:' | awk '{print $6}')
        core_ms=$(echo "$out"     | grep '^Core simulation time:'             | awk '{print $4}')

        echo "parallel,$cutoff,$n,$n,$SEED,$MODE,$LANDSCAPE,$MAX_STEPS,$TOLERANCE,$timesteps,$converged,$burning,$burned,$peak,$maxchange,$core_ms,\"$cmd\"" >> "$RESULTS_FILE"
    done
done

echo "Cutoff sweep complete. Results appended to $RESULTS_FILE"
