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
#   2. cd FirelineSerial/src && make all
#   3. run the "command" column shown in that row
#
# FireTask.java is restored to its original contents (and recompiled) when
# this script finishes, whether it finishes normally or is interrupted.
#
# This script only WRITES results.txt; it does not analyse or plot it.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$ROOT_DIR/FirelineSerial/src"
FIRETASK="$SRC_DIR/FireTask.java"
RESULTS_DIR="$ROOT_DIR/FirelineSerial/test_data"
RESULTS_FILE="$RESULTS_DIR/seq_results.txt"

CUTOFFS=(1000 10000 50000 75000 100000)
SIZES=(300 400 500 600 700)

SEED=42
MODE=wildfire
LANDSCAPE=grass
MAX_STEPS=50000
TOLERANCE=0.05

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
    echo "#   1. set 'static int SEQUENTIAL_CUTOFF = <cutoff>;' in FirelineSerial/src/FireTask.java"
    echo "#   2. (cd FirelineSerial/src && make all)"
    echo "#   3. run the exact command in the 'command' column below (from FirelineSerial/src)"
    echo "implementation,cutoff,rows,columns,seed,mode,landscape,max_steps,tolerance,timesteps,converged,burning_cells,cells_burned,max_peak_temperature,max_temperature_change,core_ms,command"
} >> "$RESULTS_FILE"

for cutoff in "${CUTOFFS[@]}"; do
    sed -i.tmp "s/static int SEQUENTIAL_CUTOFF = [0-9]*;/static int SEQUENTIAL_CUTOFF = ${cutoff};/" "$FIRETASK"
    rm -f "$FIRETASK.tmp"

    ( cd "$SRC_DIR" && make all ) >/dev/null

    for n in "${SIZES[@]}"; do
        prefix="output/cutoff_${cutoff}_${n}x${n}"
        cmd="java -cp bin FirelineParallel $n $n $SEED $MODE $prefix $MAX_STEPS $TOLERANCE $LANDSCAPE"

        out="$( cd "$SRC_DIR" && eval "$cmd" )"

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
