#!/bin/bash
# run_all_cases.sh - Orchestrator for NGS Tumor Pipeline via Slurm
#
# Usage:
#   bash run_all_cases.sh [/path/to/fastq] [--dry-run]

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Default input directory
INPUT_DIR="/scratch/tmp/jschnorr/fastq"
DRY_RUN=false

# Parse arguments
for arg in "$@"; do
    if [[ "$arg" == --dry-run ]]; then
        DRY_RUN=true
    elif [[ -d "$arg" ]]; then
        INPUT_DIR="$arg"
    fi
done

if [ ! -d "$INPUT_DIR" ]; then
    echo "Error: Input directory $INPUT_DIR not found."
    exit 1
fi

echo "Scanning for FASTQ pairs in: $INPUT_DIR"
echo "Results will be saved in: $RESULTS_BASE"

mkdir -p "$SCRATCH_DIR/slurm_logs"
mkdir -p "$RESULTS_BASE"

submitted=0

# Find all R1 files and derive the matching R2
while IFS= read -r R1; do
    R2="${R1/_R1_/_R2_}"

    if [ ! -f "$R2" ]; then
        echo "  [SKIP] No matching R2 found for: $(basename "$R1")"
        continue
    fi

    CASE_ID=$(basename "$R1" .fastq.gz)
    CASE_LABEL="${CASE_ID%_R1_001}"

    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] Would submit $CASE_LABEL"
        echo "            R1: $R1"
        echo "            R2: $R2"
    else
        echo "  [SUBMIT] $CASE_LABEL"
        sbatch --job-name="NGS_$CASE_LABEL" \
               --cpus-per-task="$PIPELINE_THREADS" \
               --mem="$PIPELINE_MEM" \
               --time=12:00:00 \
               --partition=normal \
               --output="$SCRATCH_DIR/slurm_logs/%j_$CASE_LABEL.out" \
               --error="$SCRATCH_DIR/slurm_logs/%j_$CASE_LABEL.err" \
               "$PROJECT_DIR/ngs_tumor_pipeline.sh" "$R1" "$R2"
    fi

    (( submitted++ )) || true
done < <(find "$INPUT_DIR" -maxdepth 1 -name "*_R1_*.fastq.gz" | sort)

echo ""
echo "Finished."
echo "  Cases processed: $submitted"
