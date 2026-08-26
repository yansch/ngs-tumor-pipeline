#!/bin/bash
# run.sh - Orchestrator for NGS Tumor Pipeline
set -eo pipefail
trap 'echo "run.sh - Orchestrator failed at line $LINENO: $BASH_COMMAND" >&2' ERR

# Locate project
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults
DRY_RUN=false
KEEP_EXISTING=false
INPUT_DIR_ARG=""
MAIL_USER=""
OVERRIDES_FILE=""
PRESERVE_VARS=()
NOW=false
THIS_CASE_ONLY=""

print_usage() {
        cat <<EOF
Usage: bash run.sh [options] [input_dir]

Options:
    --only ID                      Process only case IDs matching ID.
    --dry-run                      Scan and print detected cases only.
    --keep-existing                Do not clear tmp/output before run.
    --now                          Skip update check and active file transfer check.
    --mail-user EMAIL              Send Slurm mail notifications to EMAIL.
    --mail-user=EMAIL              Same as above.
    --set KEY=VALUE                Override any scalar config variable (repeatable).
    --overrides-file PATH          Source a Bash overrides file after host config.
    --help                         Show this help.
EOF
}

# --- 1. Argument Parsing ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            print_usage
            exit 0
            ;;
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
        --only=*)
            THIS_CASE_ONLY="${1#*=}"
            shift
            ;;
        --only)
            if [[ $# -gt 1 && "$2" != --* ]]; then
                THIS_CASE_ONLY="$2"
                shift 2
            else
                echo "❌ Error: --only requires a case identifier argument."
                exit 1
            fi
            ;;
        --overrides-file=*)
            OVERRIDES_FILE="${1#*=}"
            shift
            ;;
        --overrides-file)
            if [[ $# -gt 1 && "$2" != --* ]]; then
                OVERRIDES_FILE="$2"
                shift 2
            else
                echo "❌ Error: --overrides-file requires a file path argument."
                exit 1
            fi
            ;;
        --set=*)
            assignment="${1#*=}"
            if [[ "$assignment" != *=* ]]; then
                echo "❌ Error: --set requires KEY=VALUE."
                exit 1
            fi
            key="${assignment%%=*}"
            value="${assignment#*=}"
            if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
                echo "❌ Error: Invalid variable name in --set: $key"
                exit 1
            fi
            export "$key=$value"
            PRESERVE_VARS+=("$key")
            shift
            ;;
        --set)
            if [[ $# -gt 1 && "$2" != --* ]]; then
                assignment="$2"
                if [[ "$assignment" != *=* ]]; then
                    echo "❌ Error: --set requires KEY=VALUE."
                    exit 1
                fi
                key="${assignment%%=*}"
                value="${assignment#*=}"
                if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
                    echo "❌ Error: Invalid variable name in --set: $key"
                    exit 1
                fi
                export "$key=$value"
                PRESERVE_VARS+=("$key")
                shift 2
            else
                echo "❌ Error: --set requires KEY=VALUE."
                exit 1
            fi
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
            elif [[ -n "$1" && "$1" != --* ]]; then
                INPUT_DIR_ARG="$1"
            fi
            shift
            ;;
    esac
done

# Pass override metadata into all scripts that source config/common.sh.
if [[ -n "$OVERRIDES_FILE" ]]; then
    if [[ ! -f "$OVERRIDES_FILE" ]]; then
        echo "❌ Error: overrides file not found: $OVERRIDES_FILE"
        exit 1
    fi
    export NGS_CONFIG_OVERRIDES_FILE="$OVERRIDES_FILE"
fi

if [[ ${#PRESERVE_VARS[@]} -gt 0 ]]; then
    # De-duplicate while preserving first-seen order.
    declare -A seen_vars=()
    unique_vars=()
    for var_name in "${PRESERVE_VARS[@]}"; do
        if [[ -z "${seen_vars[$var_name]+x}" ]]; then
            seen_vars["$var_name"]=1
            unique_vars+=("$var_name")
        fi
    done
    export NGS_CONFIG_PRESERVE_VARS="$(IFS=,; echo "${unique_vars[*]}")"
fi

# Source configuration after parsing args so --set / --overrides-file can be applied.
source "$SCRIPT_DIR/config/common.sh"

INPUT_DIR="${INPUT_DIR_ARG:-$INPUT_DIR}"

if [ ! -d "$INPUT_DIR" ]; then
    echo "❌ Error: Input directory $INPUT_DIR not found."
    exit 1
fi

# Check for Updates (skip if --now or --dry-run is passed)
if [ "$NOW" = false ] && [ "$DRY_RUN" = false ]; then
    update_check
fi

# --- 2. Environment Initialization ---
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
layout
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
layout

mkdir -p "$RESULTS_BASE" "$SCRATCH_DIR"

if [ "$DRY_RUN" = false ] && [ "$KEEP_EXISTING" = false ]; then
    if [[ -z "$THIS_CASE_ONLY" ]]; then
        rm -rf "$SCRATCH_DIR/tmp" "$RESULTS_BASE"
        mkdir -p "$SCRATCH_DIR/tmp" "$RESULTS_BASE"
    fi
fi

if [ "$NOW" = false ] && [ "$DRY_RUN" = false ]; then
    GET_SIZE() {
        du -sb "$INPUT_DIR" 2>/dev/null | awk '{print $1}'
    }

    wait_minutes="${WAIT_TIME:-5}"
    if [ -z "$wait_minutes" ] || [ "$wait_minutes" -eq 0 ]; then
        wait_minutes=5
    fi
    SLEEPTIMER=$(echo "scale=0; $wait_minutes * 60" | bc)
    PREV_SIZE=$(GET_SIZE)

    for ((i=0; i<=wait_minutes; i++)); do
        filled=$i
        empty=$((wait_minutes - i))
        bar_filled=$(printf '%*s' "$filled" '' | tr ' ' '#')
        bar_empty=$(printf '%*s' "$empty" '' | tr ' ' '-')
        printf '\r⚙ [SAFETY][%s%s]\tChecking for active file transfer in %s. Skip by passing --now.' "$bar_filled" "$bar_empty" "$INPUT_DIR"
        sleep 1
    done
    echo ""

    CUR_SIZE=$(GET_SIZE)

    while true; do
        TIMECHECK=$(date +"%H:%M:%S")
        if [ "$PREV_SIZE" -lt "$CUR_SIZE" ]; then
            printf '\r⚙\t\t\tFile transfer still active. Last checked at [ %s ]. Checking again in %s minutes.' "$TIMECHECK" "$wait_minutes"
            sleep "$SLEEPTIMER"
            PREV_SIZE=$(GET_SIZE)
            sleep 5
            CUR_SIZE=$(GET_SIZE)
        elif [ "$PREV_SIZE" -eq "$CUR_SIZE" ]; then
            TIMECHECK=$(date +"%H:%M:%S - %d.%m.%Y")
            layout '='
            printf '⚙\t\t\tFile transfer finished at [ %s ]\n' "$TIMECHECK"
            layout '='
            break
        else
            break
        fi
    done
fi

submitted=0

# --- 3. Processing Loop ---
while IFS= read -r R1; do
    R2="${R1/_R1_/_R2_}"

    if [ ! -f "$R2" ]; then
        echo -e " ⚠️ [SKIP]\t\tMissing R2 for: $(basename "$R1")"
        continue
    fi

    CASE_ID=$(basename "$R1" .fastq.gz)
    CASE_LABEL="${CASE_ID%_R1_001}"

    if [ "$DRY_RUN" = true ]; then
        echo -e " 🔍 [DRY-RUN]\tFound: $CASE_LABEL"
        (( submitted++ )) || true
        continue
    fi

    # --- Dispatch Logic ---
    case "$PIPELINE_HOST" in
        palma)
            echo -e " 📤 [PALMA]\t\tCalculating dynamic runtime limit for: $CASE_LABEL"
            R1_size=$(wc -c < "$R1")
            R2_size=$(wc -c < "$R2")

            combined_bytes=$(( R1_size + R2_size ))
            combined_size_gb=$(printf "%.2f" "$(echo "scale=2; $combined_bytes / 1073741824" | bc)")

            # Hybrid runtime calculation: empirical factor (s/GB) * safety multiplier, rounded up to 30m (1800s), bounded between MIN (30m) and MAX (48h)
            raw_seconds=$(echo "scale=0; ($combined_bytes * ${PIPELINE_TIME_FACTOR:-1896} * ${PIPELINE_TIME_SAFETY:-1.3}) / 1073741824" | bc)
            raw_seconds=$(printf "%.0f" "$raw_seconds")
            calculated_time_needed=$(( ((raw_seconds + 1799) / 1800) * 1800 ))

            min_time="${PIPELINE_TIME_MIN:-1800}"
            max_time="${PIPELINE_TIME_MAX:-172800}"

            if (( calculated_time_needed < min_time )); then
                calculated_time_needed=$min_time
            elif (( calculated_time_needed > max_time )); then
                calculated_time_needed=$max_time
            fi

            hours=$(( calculated_time_needed / 3600 ))
            mins=$(( (calculated_time_needed % 3600) / 60 ))
            secs=$(( calculated_time_needed % 60 ))

            duration=$(printf "%02d:%02d:%02d" $hours $mins $secs)
            echo -e " 📤 [PALMA]\t\tSubmitting Slurm job: $CASE_LABEL | size: ${combined_size_gb} GB | estimated limit: $duration"

            LOG_DIR="$RESULTS_BASE/${CASE_LABEL}/log"
            mkdir -p "$LOG_DIR"
            
            SBATCH_ARGS=(
                --job-name="NGS_$CASE_LABEL"
                --export=ALL
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
            
            id=$(sbatch "${SBATCH_ARGS[@]}" "$PROJECT_DIR/ngs_tumor_pipeline.sh" "$R1" "$R2")
            printf ' 📤 [PALMA JOB]\t%s\n' "$id"
            ;;
        omen)
            echo -e " 🚀 [OMEN]\t\tExecuting local run: $CASE_LABEL"
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
layout '='
if [ "$submitted" -eq 0 ]; then
    echo "❌ Error: No matching cases were found!"
    if [ -n "$(find "$INPUT_DIR" -mindepth 1 -maxdepth 1 -type d -print -quit 2>/dev/null)" ]; then
        echo "   Make sure all FASTQ files are placed directly in $INPUT_DIR, and not nested inside subfolders!"
        echo "   At least 1 subfolder was detected in the input directory."
    else
        echo "   No valid *_R1_*.fastq.gz files found in $INPUT_DIR."
    fi
    exit 1
else
    echo -e "😊 Submitted cases:\t$submitted"
    [ "$DRY_RUN" = true ] && echo -e "   Note:\t\tDry-run complete. No jobs were executed."
    if [ "$PIPELINE_HOST" = "palma" ]; then
        echo -e "   Tip:\t\t\tuse 'bash monitor_jobs.sh' to check Palma job status and logs."
    fi
fi
layout '='