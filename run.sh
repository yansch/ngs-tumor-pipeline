#!/bin/bash
# run.sh - Orchestrator for NGS Tumor Pipeline
set -eo pipefail
trap 'echo "run.sh - Orchestrator failed at line $LINENO: $BASH_COMMAND" >&2' ERR

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config/common.sh"

# Defaults
DRY_RUN=false
KEEP_EXISTING=false
INPUT_DIR_ARG=""
MAIL_USER=""
NOW=false
TIMELOG=false #currently not implemented in main pipelines, dev function
THIS_CASE_ONLY=""

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
        --now)
            NOW=true
            shift
            ;;
        --timelog)
            TIMELOG=true
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
        --only)
            if [[ $# -gt 1 && "$2" != --* ]]; then
                THIS_CASE_ONLY="$2"
                shift 2
            else
                echo "❌ Error: --only requires a valid case identifier."
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
echo "----------------------------------------------------------------------------------------------------------------"
echo -e "🧬 Host detected:\t$PIPELINE_HOST"
echo -e "📂 Scanning path:\t$INPUT_DIR"
echo -e "📊 Results path:\t$RESULTS_BASE"
if [ -n "$MAIL_USER" ]; then
    echo -e "📧 Slurm email:\t\t$MAIL_USER"
fi
if [ "$KEEP_EXISTING" = true ] || [ -n "$THIS_CASE_ONLY" ]; then
    echo -e "🧹 Cleanup:\t\tpreserving existing tmp/output"
    if [[ -n "$THIS_CASE_ONLY" ]]; then
        echo -e "🧹\t\t\tSkipped Cleanup because --only option was given"
    fi
else
    echo -e "🧹 Cleanup:\t\tclearing tmp/output before run"
fi


mkdir -p "$RESULTS_BASE" "$SCRATCH_DIR"

if [ "$DRY_RUN" = false ] && [ "$KEEP_EXISTING" = false ]; then
    if [[ -z "$THIS_CASE_ONLY" ]]; then
        rm -rf "$SCRATCH_DIR/tmp" "$RESULTS_BASE"
        mkdir -p "$SCRATCH_DIR/tmp" "$RESULTS_BASE"
    fi
fi

if [ "$NOW" = false ]; then
#safety function, checks if a file transfer into input dir is still running or not. Default enabled, skip by passing --now
GET_SIZE() {
  # total bytes used by files in directory
  du -sb "$INPUT_DIR" 2>/dev/null | awk '{print $1}'
}

if [ -n "$WAIT_TIME" ] || [ "$WAIT_TIME" -eq 0 ]; then
    WAIT_TIME=5 #safety setting, in case Wait time isnt externally set or set to 0
fi

SLEEPTIMER=$(echo "scale=0; $WAIT_TIME * 60" | bc) 
PREV_SIZE=$(GET_SIZE) #quick check if a file transfer is running with a small loading bar

for ((i=0; i<=WAIT_TIME; i++)); do
    filled=$i
    empty=$((WAIT_TIME - i))

    # Loading Bar for initial check
    bar_filled=$(printf '%*s' "$filled" '' | tr ' ' '#')
    bar_empty=$(printf '%*s' "$empty" '' | tr ' ' '-')

    # \r = carriage return (overwrite same line) \n breaks it
    printf '\r⚙ [SAFETY][%s%s]\tChecking for active file transfer. Skip by passing --now.' "$bar_filled" "$bar_empty" 

    sleep 1
done

echo 

CUR_SIZE=$(GET_SIZE)

while true; do
    TIMECHECK=$(date +"%H:%M:%S")
    if [ "$PREV_SIZE" -lt "$CUR_SIZE" ]; then
        
        printf '\r⚙\t\t\tFile transfer still active. Last checked at [ %s ]. Checking again in %s minutes.' "$TIMECHECK" "$WAIT_TIME"
           
        sleep $SLEEPTIMER
        PREV_SIZE=$(GET_SIZE)
        sleep 5
        CUR_SIZE=$(GET_SIZE)
    
    elif [ "$PREV_SIZE" -eq "$CUR_SIZE" ]; then
        TIMECHECK=$(date +"%H:%M:%S - %d.%m.%Y")
        echo "----------------------------------------------------------------------------------------------------------------" 
        printf '⚙\t\t\tFile transfer finished at [ %s ]' "$TIMECHECK"
        echo
        break
    fi
done
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
        echo -e "🔍 [DRY-RUN]\t\tFound: $CASE_LABEL"
        (( submitted++ )) || true
        continue
    fi

    # --- Dispatch Logic ---
    case "$PIPELINE_HOST" in
        palma)
            echo -e "📤 [PALMA]\t\tCalculating dynamic runtime limit for: $CASE_LABEL"
            R1_size=$(wc -c < "$R1")
            R2_size=$(wc -c < "$R2")
            
            combined_bytes=$(( R1_size + R2_size ))
            combined_size_gb=$(printf "%.2f" "$(echo "scale=2; $combined_bytes / 1073741824" | bc)")

            # Ensure a minimum time limit of 30 minutes (1800 seconds)
            calculated_time_needed=$(( combined_bytes * PIPELINE_TIME_FACTOR / 1073741824 ))
            if (( calculated_time_needed < 1800 )); then
                calculated_time_needed=1800
            fi

            hours=$(( calculated_time_needed / 3600 ))
            mins=$(( (calculated_time_needed % 3600) / 60 ))
            secs=$(( calculated_time_needed % 60 ))

            duration=$(printf "%02d:%02d:%02d" $hours $mins $secs)
            echo -e "📤 [PALMA]\t\tSubmitting Slurm job: $CASE_LABEL | size: ${combined_size_gb} GB | estimated max runtime: $duration"

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
                --parsable
            )
            
            if [ -n "$MAIL_USER" ]; then
                SBATCH_ARGS+=(
                    --mail-user="$MAIL_USER"
                    --mail-type=ALL
                )
            fi

            if [ "$TIMELOG" = true ]; then
                       
                id=$(sbatch "${SBATCH_ARGS[@]}" "$PROJECT_DIR/ngs_tumor_pipeline.sh" "$R1" "$R2" "--timelog")

            else
                id=$(sbatch "${SBATCH_ARGS[@]}" "$PROJECT_DIR/ngs_tumor_pipeline.sh" "$R1" "$R2")
            
            fi
            printf '📤 [PALMA JOB]\t\t%s\n' "$id"  #for nice formatting only, in line with other formatting
            ;;
        omen)
            echo -e "🚀 [OMEN]\t\tExecuting local run: $CASE_LABEL"
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
done < <(find "$INPUT_DIR" -maxdepth 1 -name "*$THIS_CASE_ONLY*_R1_*.fastq.gz" | sort)

# --- 4. Summary ---
echo "----------------------------------------------------------------------------------------------------------------"
echo -e "😊 Submitted cases:\t$submitted"
[ "$DRY_RUN" = true ] && echo -e "   Note:\t\tDry-run complete. No jobs were executed."
if [ "$PIPELINE_HOST" = "palma" ]; then
    echo -e "   Tip:\t\t\tuse 'bash monitor_jobs.sh' to check Palma job status and logs."
    if [ "$TIMELOG" = true ]; then
        echo -e "⚙\t\t\tTime logging has been enabled for all jobs. Runtimes for each step will be captured."
    fi
fi
echo "----------------------------------------------------------------------------------------------------------------"