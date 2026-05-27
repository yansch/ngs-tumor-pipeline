#!/bin/bash
# run.sh - Orchestrator for NGS Tumor Pipeline
set -eo pipefail

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config/common.sh"

# Defaults
DRY_RUN=false
INPUT_DIR_ARG=""

# --- 1. Argument Parsing ---
for arg in "$@"; do
    if [[ "$arg" == --dry-run ]]; then
        DRY_RUN=true
    elif [[ -d "$arg" ]]; then
        INPUT_DIR_ARG="$arg"
    fi
done

INPUT_DIR="${INPUT_DIR_ARG:-$INPUT_DIR}"

if [ ! -d "$INPUT_DIR" ]; then
    echo "❌ Error: Input directory $INPUT_DIR not found."
    exit 1
fi

# --- 2. Environment Initialization ---
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
echo "-------------------------------------------------------"
echo "🧬 Host detected:  $PIPELINE_HOST"
echo "📂 Scanning path:  $INPUT_DIR"
echo "📊 Results path:   $RESULTS_BASE"
echo "-------------------------------------------------------"

mkdir -p "$RESULTS_BASE" "$SCRATCH_DIR"
[ "$PIPELINE_HOST" = "palma" ] && mkdir -p "$SCRATCH_DIR/slurm_logs"

submitted=0

# --- 3. Processing Loop ---
while IFS= read -r R1; do
    R2="${R1/_R1_/_R2_}"

    if [ ! -f "$R2" ]; then
        echo " ⚠️ [SKIP] Missing R2 for: $(basename "$R1")"
        continue
    fi

    CASE_ID=$(basename "$R1" .fastq.gz)
    CASE_LABEL="${CASE_ID%_R1_001}"

    if [ "$DRY_RUN" = true ]; then
        echo " 🔍 [DRY-RUN] Found: $CASE_LABEL"
        (( submitted++ )) || true
        continue
    fi

    # --- Dispatch Logic ---
    case "$PIPELINE_HOST" in
        palma)
            echo " 📤 [PALMA] Submitting Slurm job: $CASE_LABEL"
            sbatch --job-name="NGS_$CASE_LABEL" \
                   --cpus-per-task="$PIPELINE_THREADS" \
                   --mem="$PIPELINE_MEM" \
                   --time="$PIPELINE_TIME" \
                   --partition="$PIPELINE_PARTITION" \
                   --output="$SCRATCH_DIR/slurm_logs/%j_${CASE_LABEL}_${TIMESTAMP}.out" \
                   --error="$SCRATCH_DIR/slurm_logs/%j_${CASE_LABEL}_${TIMESTAMP}.err" \
                   "$PROJECT_DIR/ngs_tumor_pipeline.sh" "$R1" "$R2"
            ;;
        omen)
            echo " 🚀 [OMEN] Executing local run: $CASE_LABEL"
            LOG_DIR="$RESULTS_BASE/${CASE_LABEL}/log"
            mkdir -p "$LOG_DIR"
            LOG_FILE="$LOG_DIR/pipeline_${TIMESTAMP}.log"
            
            # Direct execution with real-time log mirroring
            bash "$PROJECT_DIR/ngs_tumor_pipeline.sh" "$R1" "$R2" 2>&1 | tee "$LOG_FILE"
            ;;
        *)
            echo "❌ Error: Unknown PIPELINE_HOST '$PIPELINE_HOST'. Check config."
            exit 1
            ;;
    esac

    (( submitted++ )) || true
done < <(find "$INPUT_DIR" -maxdepth 1 -name "*_R1_*.fastq.gz" | sort)

# --- 4. Summary ---
echo "-------------------------------------------------------"
echo "😊 Submitted cases: $submitted"
[ "$DRY_RUN" = true ] && echo "   Note: Dry-run complete. No jobs were executed."
echo "-------------------------------------------------------"