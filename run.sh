#!/bin/bash
# run.sh - Orchestrator for NGS Tumor Pipeline
set -eo pipefail
trap 'echo "? Pipeline failed at line $LINENO: $BASH_COMMAND" >&2' ERR

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config/common.sh"

# Defaults
DRY_RUN=false
KEEP_EXISTING=false
TIMELOG=false
INPUT_DIR_ARG=""
MAIL_USER="yannisluca.adrian@ukmuenster.de"

# --- 1. Argument Parsing ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --timelog)
            TIMELOG=true
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
                echo "? Error: --mail-user requires an email address argument."
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
    echo "? Error: Input directory $INPUT_DIR not found."
    exit 1
fi

# --- 2. Environment Initialization ---
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
echo "-------------------------------------------------------"
echo "?? Host detected:  $PIPELINE_HOST"
echo "?? Scanning path:  $INPUT_DIR"
echo "?? Results path:   $RESULTS_BASE"
if [ -n "$MAIL_USER" ]; then
    echo "?? Slurm email:    $MAIL_USER"
fi
if [ "$KEEP_EXISTING" = true ]; then
    echo "?? Cleanup:        preserving existing tmp/output"
else
    echo "?? Cleanup:        clearing tmp/output before run"
fi
echo "-------------------------------------------------------"

mkdir -p "$RESULTS_BASE" "$SCRATCH_DIR"

if [ "$DRY_RUN" = false ] && [ "$KEEP_EXISTING" = false ]; then
    rm -rf "$SCRATCH_DIR/tmp" "$RESULTS_BASE"
    mkdir -p "$SCRATCH_DIR/tmp" "$RESULTS_BASE"
fi

wartezeit=10 #in minuten (wartezeit zwischen den prüfungen, ob der Transfer der Dateien noch läuft oder abgeschlossen ist)
get_size() {
  # total bytes used by files in directory
  du -sb ~+/input 2>/dev/null | awk '{print $1}'
}
sleeptimer=$(echo "scale=0; $wartezeit * 60" | bc) 
prev_size=$(get_size) #quick check if a file transfer is running
sleep 5
cur_size=$(get_size)

while true; do
    if [ "$prev_size" -lt "$cur_size" ]
    then
    echo -e "$(date '+%H:%M:%S') - Kopiervorgang noch im Gange, es wird gewartet..."
    sleep $sleeptimer
    prev_size=$(get_size)
    sleep 5
    cur_size=$(get_size)
    
    elif [ "$prev_size" -eq "$cur_size" ]
    then
    echo "Kopiervorgang abgeschlossen"
    break
    fi
done



submitted=0

# --- 3. Processing Loop ---
while IFS= read -r R1; do
    R2="${R1/_R1_/_R2_}"

    if [ ! -f "$R2" ]; then
        echo " ?? [SKIP] Missing R2 for: $(basename "$R1")"
        continue
    fi

    CASE_ID=$(basename "$R1" .fastq.gz)
    CASE_LABEL="${CASE_ID%_R1_001}"

    if [ "$DRY_RUN" = true ]; then
        echo " ?? [DRY-RUN] Found: $CASE_LABEL"
        (( submitted++ )) || true
        continue
    fi

    # --- Dispatch Logic ---
    case "$PIPELINE_HOST" in
        palma)
            echo " ?? [PALMA] Calculating dynamic runtime limit for: $CASE_LABEL"
            R1_size=$(wc -c < "$R1")
            R2_size=$(wc -c < "$R2")
            #x=1896  # Time needed per GB in seconds, based on NovaseqX data by YA

            combined_bytes=$(( R1_size + R2_size ))
            combined_size_gb=$(printf "%.2f" "$(echo "scale=2; $combined_bytes / 1073741824" | bc)")

            # Ensure a minimum time limit of 30 minutes (1800 seconds)
            calculated_time_needed=$(( combined_bytes * PIPELINE_TIME_FACTOR / 1073741824 ))
            if (( calculated_time_needed < 7200 )); then #normally 1800
                calculated_time_needed=7200
            fi

            hours=$(( calculated_time_needed / 3600 ))
            mins=$(( (calculated_time_needed % 3600) / 60 ))
            secs=$(( calculated_time_needed % 60 ))

            duration=$(printf "%02d:%02d:%02d" $hours $mins $secs)
            echo " ?? [PALMA] Submitting Slurm job: $CASE_LABEL | size: ${combined_size_gb} GB | estimated limit: $duration"

            LOG_DIR="$RESULTS_BASE/${CASE_LABEL}/log"
            mkdir -p "$LOG_DIR"
            
            SBATCH_ARGS=(
                --job-name="NGS_$CASE_LABEL"
                --cpus-per-task="$PIPELINE_THREADS"
#                --cpus-per-task="2"
                --mem="$PIPELINE_MEM"
#                --mem="2G"
                --time="$duration"
#                --time="00:02:00"
                --partition="$PIPELINE_PARTITION"
#                --partition="express"
                --output="$LOG_DIR/%j_${CASE_LABEL}_${TIMESTAMP}.out"
                --error="$LOG_DIR/%j_${CASE_LABEL}_${TIMESTAMP}.err"
            )
            
            if [ -n "$MAIL_USER" ]; then
                SBATCH_ARGS+=(
                    --mail-user="$MAIL_USER"
                    --mail-type=ALL
                )
            fi
            
            if [ "$TIMELOG" = true ]; then
              sbatch "${SBATCH_ARGS[@]}" "$PROJECT_DIR/kraken2.sh" "$R1" "$R2" "--timelog"
              
            else
              sbatch "${SBATCH_ARGS[@]}" "$PROJECT_DIR/kraken2.sh" "$R1" "$R2"
              
            fi 
            
#             
#             
#             if [ "$TIMELOG" = true ]; then
#                 #sbatch "${SBATCH_ARGS[@]}" "$PROJECT_DIR/ngs_tumor_pipeline.sh" "$R1" "$R2" "--timelog"
#                  
#                 sbatch "${SBATCH_ARGS[@]}" "$PROJECT_DIR/kraken2.sh" "$R1" "$R2" "--timelog"
#                 
#             else
#                 #sbatch "${SBATCH_ARGS[@]}" "$PROJECT_DIR/ngs_tumor_pipeline.sh" "$R1" "$R2" 
#                 sbatch "${SBATCH_ARGS[@]}" "$PROJECT_DIR/kraken2.sh" "$R1" "$R2"
#                          
#             fi
            

            
            ;;
        omen)
            echo " ?? [OMEN] Executing local run: $CASE_LABEL"
            LOG_DIR="$RESULTS_BASE/${CASE_LABEL}/log"
            mkdir -p "$LOG_DIR"
            LOG_FILE="$LOG_DIR/pipeline_${TIMESTAMP}.log"
            
            # Direct execution with real-time log mirroring
            bash "$PROJECT_DIR/ngs_tumor_pipeline.sh" "$R1" "$R2" 2>&1 | tee "$LOG_FILE"
            ;;
        *)
            echo "? Error: Unknown PIPELINE_HOST '$PIPELINE_HOST'. Check config."
            exit 1
            ;;
    esac

    (( submitted++ )) || true
done < <(find "$INPUT_DIR" -maxdepth 1 -name "*_R1_*.fastq.gz" | sort)

# --- 4. Summary ---
echo "-------------------------------------------------------"
echo "?? Submitted cases: $submitted"
[ "$DRY_RUN" = true ] && echo "   Note: Dry-run complete. No jobs were executed."
if [ "$PIPELINE_HOST" = "palma" ]; then
    echo "   Tip: use 'bash monitor_jobs.sh' to check Palma job status and logs."
fi
echo "-------------------------------------------------------"
