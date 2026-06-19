#!/bin/bash
# run.sh - Orchestrator for NGS Tumor Pipeline
set -eo pipefail

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config/common.sh"

# Defaults
DRY_RUN=false
INPUT_DIR_ARG=""
MAIL_USER=""

# --- 1. Argument Parsing ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --mail-user=*)
            MAIL_USER="${1#*=}"
            shift
            ;;
        --mail-user)
            if [[ $# -gt 1 && "$2" != --* ]]; then
                MAIL_USER="$2"
                shift 2
            else
                echo "❌ Error: --mail-user requires an email address argument."
                exit 1
            fi
            ;;
        *)
            if [[ -d "$1" ]]; then
                INPUT_DIR_ARG="$1"
            fi
            shift
            ;;
    esac
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
if [ -n "$MAIL_USER" ]; then
    echo "📧 Slurm email:    $MAIL_USER"
fi
echo "-------------------------------------------------------"

mkdir -p "$RESULTS_BASE" "$SCRATCH_DIR"

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
            LOG_DIR="$RESULTS_BASE/${CASE_LABEL}/log"
            mkdir -p "$LOG_DIR"
            
            SBATCH_ARGS=(
                --job-name="NGS_$CASE_LABEL"
                --cpus-per-task="$PIPELINE_THREADS"
                --mem="$PIPELINE_MEM"
                --time="$PIPELINE_TIME"
                --partition="$PIPELINE_PARTITION"
                --output="$LOG_DIR/%j_${CASE_LABEL}_${TIMESTAMP}.out"
                --error="$LOG_DIR/%j_${CASE_LABEL}_${TIMESTAMP}.err"
            )
            
            if [ -n "$MAIL_USER" ]; then
                SBATCH_ARGS+=(
                    --mail-user="$MAIL_USER"
                    --mail-type=ALL
                )
            fi
            
            sbatch "${SBATCH_ARGS[@]}" "$PROJECT_DIR/ngs_tumor_pipeline.sh" "$R1" "$R2"
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
if [ "$PIPELINE_HOST" = "palma" ]; then
    echo "   Tip: use 'bash monitor_jobs.sh' to check Palma job status and logs."
fi
echo "-------------------------------------------------------"