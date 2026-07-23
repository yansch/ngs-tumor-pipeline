#!/bin/bash
# components/01_fastp/run_fastp.sh
# Step 1: FASTQ quality control and adapter trimming with fastp
#
# Expects (set by orchestrator):
#   R1_PATH, R2_PATH, R1_TRIMMED, R2_TRIMMED, FASTP_DIR, FASTP_JSON
#   THREADS, FASTP_TOOLCHAIN_MODULE, FASTP_MODULES[@]
#
# Exports:
#   TOTAL_READS  - total read count extracted from fastp JSON

require_vars R1_PATH R2_PATH R1_TRIMMED R2_TRIMMED FASTP_DIR FASTP_JSON THREADS

_STEP_T0=$(date +%s)
step_start "01 · fastp — quality control & adapter trimming"

purge_modules
load_modules "$FASTP_TOOLCHAIN_MODULE" "${FASTP_MODULES[@]}"

if run_if_missing "$R1_TRIMMED" "fastp trimming"; then
    run_if_missing "$FASTP_JSON" "fastp trimming"  # treat both outputs together
    echo "   Running fastp on $(basename "$R1_PATH") + $(basename "$R2_PATH")..."
    fastp \
        -i "$R1_PATH" -I "$R2_PATH" \
        -o "$R1_TRIMMED" -O "$R2_TRIMMED" \
        -p "$THREADS" \
        --low_complexity_filter \
        -h "$FASTP_DIR/${R1_base}.fastp.html" \
        -j "$FASTP_JSON"
fi

# Extract total_reads from the JSON (jq preferred, python3 fallback)
if command -v jq &>/dev/null; then
    TOTAL_READS=$(jq -r '.summary.before_filtering.total_reads' "$FASTP_JSON")
else
    TOTAL_READS=$(python3 -c \
        "import json,sys; print(json.load(open(sys.argv[1]))['summary']['before_filtering']['total_reads'])" \
        "$FASTP_JSON")
fi
export TOTAL_READS
echo "   Total reads: $TOTAL_READS"

step_end "01 · fastp" "$_STEP_T0"
