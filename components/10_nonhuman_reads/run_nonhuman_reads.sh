#!/bin/bash
# components/10_nonhuman_reads/run_nonhuman_reads.sh
# Step 10: Extract non-human reads for metagenomics samples
#
# Expects (set by orchestrator):
#   CASE_LABEL, OUT_DIR, TMP_DIR, CNV_DIR, R1_base, R2_base
#   R1_TRIMMED, R2_TRIMMED, BOWTIE_INDEX, BOWTIE2_BIN
#   PROJECT_DIR, PIPELINE_HOST, THREADS
#   (analysis env already active; this step may temporarily load Bowtie2 on Palma)

require_vars CASE_LABEL OUT_DIR TMP_DIR CNV_DIR R1_base R2_base R1_TRIMMED R2_TRIMMED PROJECT_DIR

_STEP_T0=$(date +%s)
step_start "10 · Metagenomics — non-human read extraction"

COVERAGE_DIR="$CNV_DIR/coverage"
COVERAGE_FILE="$COVERAGE_DIR/${R1_base}_panel_coverage.txt"
METAGENOMICS_DIR="${METAGENOMICS_DIR:-$OUT_DIR/metagenomics}"
NONHUMAN_DIR="${NONHUMAN_DIR:-$METAGENOMICS_DIR/nonhuman_reads}"
NONHUMAN_R1="$NONHUMAN_DIR/${R1_base}_nonhuman_reads.fastq.gz"
NONHUMAN_R2="$NONHUMAN_DIR/${R2_base}_nonhuman_reads.fastq.gz"

if [ ! -f "$COVERAGE_FILE" ]; then
    echo "   ℹ️  Coverage file not found at $COVERAGE_FILE — skipping non-human read extraction."
    step_end "10 · Metagenomics" "$_STEP_T0"
    return 0 2>/dev/null || exit 0
fi

mean_coverage=$(awk -F'\t' '{sum += $3; n++} END {if (n > 0) printf "%.2f", sum / n; else print "0"}' "$COVERAGE_FILE")
echo "   Mean panel coverage: $mean_coverage"

if ! awk -v m="$mean_coverage" 'BEGIN { exit !(m <= 100) }'; then
    echo "   Normal diagnostic case detected — skipping non-human read extraction."
    step_end "10 · Metagenomics" "$_STEP_T0"
    return 0 2>/dev/null || exit 0
fi

require_vars BOWTIE_INDEX BOWTIE2_BIN

if [ ! -d "$BOWTIE_INDEX" ]; then
    echo "❌ Bowtie2 index not found: $BOWTIE_INDEX" >&2
    echo "   Set BOWTIE_INDEX in your host config or .env file before running metagenomics cases." >&2
    exit 1
fi

if run_if_missing "$NONHUMAN_R1" "non-human read extraction"; then
    mkdir -p "$NONHUMAN_DIR"

    if [ "$PIPELINE_HOST" = "palma" ]; then
        purge_modules
        load_modules "$BOWTIE2_TOOLCHAIN_MODULE" "${BOWTIE2_MODULES[@]}"
    fi

    if [ -x "$BOWTIE2_BIN" ]; then
        BOWTIE2_CMD="$BOWTIE2_BIN"
    elif command -v "$BOWTIE2_BIN" >/dev/null 2>&1; then
        BOWTIE2_CMD="$BOWTIE2_BIN"
    else
        echo "❌ Bowtie2 binary not found: $BOWTIE2_BIN" >&2
        exit 1
    fi

    echo "   Running Bowtie2 host depletion..."
    "$BOWTIE2_CMD" -x "$BOWTIE_INDEX" -p "$THREADS" -1 "$R1_TRIMMED" \
        -2 "$R2_TRIMMED" \
        --un-conc-gz "$TMP_DIR/${R1_base}_nonhuman_reads" \
        -S /dev/null

    mv "$TMP_DIR/${R1_base}_nonhuman_reads.1" "$NONHUMAN_R1"
    mv "$TMP_DIR/${R1_base}_nonhuman_reads.2" "$NONHUMAN_R2"
    echo "   Non-human reads written to $NONHUMAN_DIR"
fi

step_end "10 · Metagenomics" "$_STEP_T0"
