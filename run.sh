#!/bin/bash
# run.sh - Orchestrator for NGS Tumor Pipeline
#
# Usage:
#   bash run.sh [/path/to/fastq] [--dry-run]

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config/common.sh"

# Default input directory from config
DRY_RUN=false

# Parse arguments
INPUT_DIR_ARG=""
for arg in "$@"; do
    if [[ "$arg" == --dry-run ]]; then
        DRY_RUN=true
    elif [[ -d "$arg" ]]; then
        INPUT_DIR_ARG="$arg"
    fi
done

# Priority: CLI argument > config.sh
INPUT_DIR="${INPUT_DIR_ARG:-$INPUT_DIR}"

if [ ! -d "$INPUT_DIR" ]; then
    echo "Error: Input directory $INPUT_DIR not found."
    exit 1
fi

echo "Host detected: $PIPELINE_HOST"
echo "Scanning for FASTQ pairs in: $INPUT_DIR"
echo "Results will be saved in: $RESULTS_BASE"

# Create base directories
mkdir -p "$RESULTS_BASE" "$SCRATCH_DIR"
if [ "$PIPELINE_HOST" = "palma" ]; then
    mkdir -p "$SCRATCH_DIR/slurm_logs"
fi

submitted=0
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

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
        echo "  [DRY-RUN] Would process $CASE_LABEL"
        echo "            R1: $R1"
        echo "            R2: $R2"
    else
        # Dispatch logic
        if [ "$PIPELINE_HOST" = "palma" ]; then
            echo "  [SUBMIT] $CASE_LABEL (Slurm)"
            sbatch --job-name="NGS_$CASE_LABEL" \
                   --cpus-per-task="$PIPELINE_THREADS" \
                   --mem="$PIPELINE_MEM" \
                   --time="$PIPELINE_TIME" \
                   --partition="$PIPELINE_PARTITION" \
                   --output="$SCRATCH_DIR/slurm_logs/%j_${CASE_LABEL}_${TIMESTAMP}.out" \
                   --error="$SCRATCH_DIR/slurm_logs/%j_${CASE_LABEL}_${TIMESTAMP}.err" \
                   "$PROJECT_DIR/ngs_tumor_pipeline.sh" "$R1" "$R2"
        elif [ "$PIPELINE_HOST" = "omen" ]; then
            echo "  [RUN] $CASE_LABEL (Direct)"
            mkdir -p "$RESULTS_BASE/${CASE_LABEL}/log"
            LOG_FILE="$RESULTS_BASE/${CASE_LABEL}/log/pipeline_${TIMESTAMP}.log"
            bash "$PROJECT_DIR/ngs_tumor_pipeline.sh" "$R1" "$R2" 2>&1 | tee "$LOG_FILE"
            echo "    Done. Log: $LOG_FILE"
        else
            echo "  [RUN] $CASE_LABEL (Background)"
            mkdir -p "$RESULTS_BASE/${CASE_LABEL}/log"
            LOG_FILE="$RESULTS_BASE/${CASE_LABEL}/log/pipeline_${TIMESTAMP}.log"
            bash "$PROJECT_DIR/ngs_tumor_pipeline.sh" "$R1" "$R2" > "$LOG_FILE" 2>&1 &
            echo "    Log: $LOG_FILE"
        fi
    fi

    (( submitted++ )) || true
done < <(find "$INPUT_DIR" -maxdepth 1 -name "*_R1_*.fastq.gz" | sort)

echo ""
echo "Finished."
echo "  Cases processed: $submitted"
if [ "$DRY_RUN" = false ]; then
    if [ "$PIPELINE_HOST" = "palma" ]; then
        echo "  Jobs have been submitted to Slurm."
    elif [ "$PIPELINE_HOST" != "omen" ]; then
        echo "  Jobs are running in the background. Check logs for progress."
    fi
fi
