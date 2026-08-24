#!/usr/bin/env bash
set -euo pipefail

# Paired serial-vs-parallel benchmark for the Fireline parallel assignment.
#
# For each of 5 grid sizes (100x100, 200x200, 300x300, 400x400, 500x500)
# this runs 10 different seeds (1..10), each executed once with
# FirelineSerial and once with FirelineParallel: 20 runs per grid size
# (10 parallel, 10 serial), 100 runs in total.
#
# Note: the landscape used here is 'grass', and the serial program
# disregards the seed for the grass landscape (see
# CSC2002S_PCP1_Assignment_2026_Fireline.pdf, section 2.1), so the terrain
# and ignition patch are identical across seeds. Each seed is still passed
# through and recorded so every row is individually reproducible, and the
# 10 runs per implementation/size serve as independent timing repetitions
# for reliability (e.g. computing a mean/median core simulation time).
#
# FireTask.SEQUENTIAL_CUTOFF is left exactly as currently defined in
# FireTask.java (this script does not modify it); the value in effect at
# run time is read from the source file and recorded in every row.
#
# Every result row records every value needed to run the exact same
# scenario again by hand: just run the "command" column shown in that row
# from FirelineSerial/src (after `make all`).
#
# This script only WRITES results.txt; it does not analyse or plot it.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$ROOT_DIR/FirelineSerial/src"
FIRETASK="$SRC_DIR/FireTask.java"
RESULTS_DIR="$ROOT_DIR/FirelineSerial/test_data"
RESULTS_FILE="$RESULTS_DIR/results.txt"

SIZES=(300 400 500 600 700)
SEEDS=(1 2 3 4 5 6 7 8 9 10)

MODE=wildfire
LANDSCAPE=grass
MAX_STEPS=50000
TOLERANCE=0.05

mkdir -p "$RESULTS_DIR"

CUTOFF_USED="unknown"
if [ -f "$FIRETASK" ]; then
    CUTOFF_USED=$(grep -o 'SEQUENTIAL_CUTOFF = [0-9]*' "$FIRETASK" | head -1 | awk '{print $3}')
fi

( cd "$SRC_DIR" && make all ) >/dev/null

{
    echo "# Serial vs parallel seed sweep - $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "# Fixed simulation parameters: mode=$MODE landscape=$LANDSCAPE max_steps=$MAX_STEPS tolerance=$TOLERANCE"
    echo "# FireTask.SEQUENTIAL_CUTOFF at run time (unmodified by this script): $CUTOFF_USED"
    echo "# To recreate any row by hand, run the exact command in the 'command' column below (from FirelineSerial/src, after 'make all')"
    echo "implementation,rows,columns,seed,mode,landscape,max_steps,tolerance,cutoff,timesteps,converged,burning_cells,cells_burned,max_peak_temperature,max_temperature_change,core_ms,command"
} >> "$RESULTS_FILE"

run_one() {
    local impl="$1" n="$2" seed="$3"
    local impl_lower
    impl_lower=$(echo "$impl" | tr '[:upper:]' '[:lower:]')
    local prefix="output/${impl_lower}_${n}x${n}_seed${seed}"
    local cmd="java -cp bin $impl $n $n $seed $MODE $prefix $MAX_STEPS $TOLERANCE $LANDSCAPE"

    local out
    out="$( cd "$SRC_DIR" && eval "$cmd" )"

    local timesteps converged burning burned peak maxchange core_ms
    timesteps=$(echo "$out"   | grep '^Timesteps completed:'              | awk '{print $3}')
    converged=$(echo "$out"   | grep '^Converged:'                        | awk '{print $2}')
    burning=$(echo "$out"     | grep '^Final burning cells:'              | awk '{print $4}')
    burned=$(echo "$out"      | grep '^Cells burned:'                     | awk '{print $3}')
    peak=$(echo "$out"        | grep '^Maximum peak temperature:'         | awk '{print $4}')
    maxchange=$(echo "$out"   | grep '^Maximum change in final timestep:' | awk '{print $6}')
    core_ms=$(echo "$out"     | grep '^Core simulation time:'             | awk '{print $4}')

    echo "$impl,$n,$n,$seed,$MODE,$LANDSCAPE,$MAX_STEPS,$TOLERANCE,$CUTOFF_USED,$timesteps,$converged,$burning,$burned,$peak,$maxchange,$core_ms,\"$cmd\"" >> "$RESULTS_FILE"
}

for n in "${SIZES[@]}"; do
    for seed in "${SEEDS[@]}"; do
        run_one FirelineParallel "$n" "$seed"
        run_one FirelineSerial "$n" "$seed"
    done
done

echo "Serial vs parallel sweep complete. Results appended to $RESULTS_FILE"
