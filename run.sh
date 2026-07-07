#!/bin/bash
# run.sh - Orchestrator for NGS Tumor Pipeline
set -eo pipefail

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config/common.sh"

# Defaults
DRY_RUN=false
KEEP_EXISTING=false
INPUT_DIR_ARG=""
MAIL_USER=""

# --- 1. Argument Parsing ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --keep-existing)
            KEEP_EXISTING=true
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
if [ "$KEEP_EXISTING" = true ]; then
    echo "🧹 Cleanup:        preserving existing tmp/output"
else
    echo "🧹 Cleanup:        clearing tmp/output before run"
fi
echo "-------------------------------------------------------"

mkdir -p "$RESULTS_BASE" "$SCRATCH_DIR"

if [ "$DRY_RUN" = false ] && [ "$KEEP_EXISTING" = false ]; then
    rm -rf "$SCRATCH_DIR/tmp" "$RESULTS_BASE"
    mkdir -p "$SCRATCH_DIR/tmp" "$RESULTS_BASE"
fi

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
            echo " 📤 [PALMA] Calculating dynamic runtime limit for: $CASE_LABEL"
            R1_size=$(wc -c < "$R1")
            R2_size=$(wc -c < "$R2")
            x=767  # Time needed per GB in seconds, based on NovaseqX data by YA

            combined_bytes=$(( R1_size + R2_size ))
            combined_size_gb=$(printf "%.2f" "$(echo "scale=2; $combined_bytes / 1073741824" | bc)")

            # Ensure a minimum time limit of 30 minutes (1800 seconds)
            calculated_time_needed=$(( combined_bytes * x / 1073741824 ))
            if (( calculated_time_needed < 1800 )); then
                calculated_time_needed=1800
            fi

            hours=$(( calculated_time_needed / 3600 ))
            mins=$(( (calculated_time_needed % 3600) / 60 ))
            secs=$(( calculated_time_needed % 60 ))

            duration=$(printf "%02d:%02d:%02d" $hours $mins $secs)
            echo " 📤 [PALMA] Submitting Slurm job: $CASE_LABEL | size: ${combined_size_gb} GB | estimated limit: $duration"

            LOG_DIR="$RESULTS_BASE/${CASE_LABEL}/log"
            mkdir -p "$LOG_DIR"
            
            SBATCH_ARGS=(
                --job-name="NGS_$CASE_LABEL"
                --cpus-per-task="$PIPELINE_THREADS"
                --mem="$PIPELINE_MEM"
                --time="$duration"
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