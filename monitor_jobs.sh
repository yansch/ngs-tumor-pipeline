#!/bin/bash
# status.sh - Monitor NGS Pipeline jobs and logs
set -eo pipefail

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config/common.sh"

if [ "$PIPELINE_HOST" != "palma" ]; then
    echo "❌ monitor_jobs.sh is only available on Palma."
    exit 1
fi

INTERVAL=10
ONCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --once|-1)
            ONCE=true
            shift
            ;;
        [0-9]*)
            INTERVAL="$1"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

format_duration() {
    local total_seconds=${1:-0}
    if (( total_seconds < 0 )); then
        total_seconds=0
    fi

    local hours=$(( total_seconds / 3600 ))
    local mins=$(( (total_seconds % 3600) / 60 ))
    local secs=$(( total_seconds % 60 ))
    printf "%02d:%02d:%02d" "$hours" "$mins" "$secs"
}

estimate_remaining_time() {
    local job_name="$1"
    local start_time="$2"
    local case_label="${job_name#NGS_}"
    local r1 r2 combined_bytes total_seconds elapsed_seconds remaining_seconds

    r1=$(find "$INPUT_DIR" -maxdepth 1 -type f -name "${case_label}_R1_*.fastq.gz" | sort | head -n 1)
    r2="${r1/_R1_/_R2_}"

    if [ -z "$r1" ] || [ ! -f "$r2" ]; then
        printf "N/A"
        return 0
    fi

    combined_bytes=$(( $(wc -c < "$r1") + $(wc -c < "$r2") ))
    total_seconds=$(( combined_bytes * PIPELINE_TIME_FACTOR / 1073741824 ))

    elapsed_seconds=$(( $(date +%s) - $(date -d "$start_time" +%s) ))
    remaining_seconds=$(( total_seconds - elapsed_seconds ))

    format_duration "$remaining_seconds"
}

render_status() {
    [ "$ONCE" = false ] && printf "\033[H\033[2J"

    echo "-------------------------------------------------------"
    echo "🔍 NGS Pipeline Status for user: $USER"
    echo "-------------------------------------------------------"

    # --- 1. Active Queue Status ---
    echo "👩🏼‍🔬  ACTIVE JOBS (squeue)"
    ACTIVE_JOBS=$(squeue -u "$USER" -o "%i|%j|%T|%M|%S|%R" --noheader | grep "NGS_" || true)

    if [ -z "$ACTIVE_JOBS" ]; then
        echo "    No active NGS jobs found in the queue."
    else
        printf "    %-10s %-20s %-10s %-10s %-10s %-s\n" "JOBID" "CASE" "STATE" "TIME" "REMAINING" "NODE/REASON"
        while IFS='|' read -r id name state time start extra; do
            remaining_time="N/A"
            if [[ "$state" == "RUNNING" && "$start" != "N/A" && "$start" != "Unknown" ]]; then
                remaining_time=$(estimate_remaining_time "$name" "$start")
            fi
            printf "    %-10s %-20s %-10s %-10s %-10s %-s\n" "$id" "$name" "$state" "$time" "$remaining_time" "$extra"
        done <<< "$ACTIVE_JOBS"
    fi

    echo ""

    # --- 2. Recent History ---
    echo "⌛ RECENT HISTORY (Last 24h)"
    # Filtering for main jobs (ignoring .batch/.extern steps)
    HISTORY=$(sacct -u "$USER" -S $(date -d "24 hours ago" +%Y-%m-%dT%H:%M) --format="JobID,JobName%25,State,ExitCode" --noheader | grep "NGS_" | grep -v "\." || true)

    ACTIVE_JOB_IDS=()
    if [ -n "$ACTIVE_JOBS" ]; then
        while IFS='|' read -r id name state time start extra; do
            [ -n "$id" ] && ACTIVE_JOB_IDS+=("$id")
        done <<< "$ACTIVE_JOBS"
    fi

    FILTERED_HISTORY=""
    while read -r id name state exitcode; do
        SKIP=false
        for active_id in "${ACTIVE_JOB_IDS[@]}"; do
            if [ "$id" = "$active_id" ]; then
                SKIP=true
                break
            fi
        done
        [ "$SKIP" = true ] && continue
        FILTERED_HISTORY+="$id $name $state $exitcode"$'\n'
    done <<< "$HISTORY"

    if [ -z "$FILTERED_HISTORY" ]; then
        echo "    No NGS job history found for the last 24 hours."
    else
        printf "    %-10s %-25s %-15s %-10s\n" "JOBID" "CASE" "STATE" "EXIT"
        while read -r id name state exitcode; do
            # Mark failures with a cross
            STATUS_ICON="❓"
            [[ "$state" == "FAILED"* ]] && STATUS_ICON="❌"
            [[ "$state" == "TIMEOUT"* ]] && STATUS_ICON="❌"
            [[ "$state" == "CANCELLED"* ]] && STATUS_ICON="🛑"
            [[ "$state" == "RUNNING" ]] && STATUS_ICON="⚙️ "
            [[ "$state" == "PENDING"* ]] && STATUS_ICON="⏳"
            [[ "$state" == "COMPLETED"* ]] && STATUS_ICON="✅"

            printf "    %-10s %-25s %-15s %-10s %s\n" "$id" "$name" "$state" "$exitcode" "$STATUS_ICON"
        done <<< "$FILTERED_HISTORY"
    fi

    echo ""

    # --- 3. Log Inspection Commands ---
    echo "📄 LOG ACCESS"

    CASES=()
    if [ -d "$RESULTS_BASE" ]; then
        while IFS= read -r dir; do
            [ -n "$dir" ] && CASES+=("$(basename "$(dirname "$dir")")")
        done < <(find "$RESULTS_BASE" -mindepth 2 -maxdepth 2 -type d -name "log" 2>/dev/null || true)
    fi

    if [ -n "$ACTIVE_JOBS" ]; then
        while IFS='|' read -r id name state time start extra; do
            case_label="${name#NGS_}"
            [ -n "$case_label" ] && CASES+=("$case_label")
        done <<< "$ACTIVE_JOBS"
    fi

    UNIQUE_CASES=$(printf "%s\n" "${CASES[@]}" 2>/dev/null | grep -v '^$' | sort -u || true)

    if [ -z "$UNIQUE_CASES" ]; then
        echo "    No log directories found under $RESULTS_BASE"
    else
        printf "    %-20s %-s\n" "CASE ID" "ABSOLUTE LOG PATH"
        while read -r case_id; do
            log_dir="$RESULTS_BASE/$case_id/log"
            abs_path=$(realpath "$log_dir" 2>/dev/null || echo "$log_dir")
            printf "    %-20s %-s\n" "$case_id" "$abs_path"
        done <<< "$UNIQUE_CASES"

        echo ""
        echo "    To view a desired log using tail -f:"
        echo "    tail -f <ABSOLUTE_LOG_PATH>/[JOBID]_*.out"
    fi

    echo "-------------------------------------------------------"
    echo "💡 Tip: Use 'scancel -u $USER' to stop all your jobs."
    if [ "$ONCE" = false ]; then
        echo "🔄 Auto-refreshing every ${INTERVAL}s. Press Ctrl+C to exit."
    fi
    echo "-------------------------------------------------------"
}

cleanup() {
    [ "$ONCE" = false ] && printf "\033[?1049l"
    exit 0
}

trap cleanup INT TERM EXIT

if [ "$ONCE" = true ]; then
    render_status
else
    printf "\033[?1049h"
    while true; do
        render_status
        sleep "$INTERVAL"
    done
fi