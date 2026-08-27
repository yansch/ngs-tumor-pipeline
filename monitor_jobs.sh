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

INTERVAL=30
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

    local term_lines
    term_lines=$(tput lines 2>/dev/null || echo "${LINES:-24}")
    if [[ ! "$term_lines" =~ ^[0-9]+$ ]] || [ "$term_lines" -lt 10 ]; then
        term_lines=24
    fi

    # Header: 3 lines (dashes + title + dashes)
    # Active jobs overhead: 2 lines (section title + empty line separator)
    # Active jobs header/empty msg: 1 line (table header or "No active jobs...")
    # History overhead: 2 lines (section title + empty line separator)
    # Log access overhead: 1 line (section title)
    # Footer: 3 lines (dashes + tip/refresh info + dashes) + 1 safety margin
    # Base overhead ≈ 12 lines
    local base_overhead=12

    # --- 1. Active Queue Status ---
    ACTIVE_JOBS=$(squeue -u "$USER" -o "%i|%j|%T|%M|%S|%R" --noheader | grep "NGS_" || true)

    local active_rows=0
    if [ -n "$ACTIVE_JOBS" ]; then
        active_rows=$(echo "$ACTIVE_JOBS" | wc -l)
    fi

    # Calculate remaining lines for History and Log Access tables
    local remaining_space=$(( term_lines - base_overhead - active_rows ))
    [ "$remaining_space" -lt 4 ] && remaining_space=4

    # Split remaining space roughly equally between History and Log Access
    local max_history_items=$(( remaining_space / 2 ))
    local max_log_items=$(( remaining_space - max_history_items ))
    [ "$max_history_items" -lt 2 ] && max_history_items=2
    [ "$max_log_items" -lt 2 ] && max_log_items=2

    echo "-------------------------------------------------------"
    echo "🔍 NGS Pipeline Status for user: $USER"
    echo "-------------------------------------------------------"

    echo "👩🏼‍🔬  ACTIVE JOBS (squeue)"
    if [ -z "$ACTIVE_JOBS" ]; then
        echo "    No active NGS jobs found in the queue."
    else
        printf "    %-10s %-50s %-10s %-10s %-10s %-s\n" "JOBID" "CASE" "STATE" "TIME" "REMAINING" "NODE/REASON"
        while IFS='|' read -r id name state time start extra; do
            remaining_time="N/A"
            if [[ "$state" == "RUNNING" && "$start" != "N/A" && "$start" != "Unknown" ]]; then
                remaining_time=$(estimate_remaining_time "$name" "$start")
            fi
            printf "    %-10s %-50s %-10s %-10s %-10s %-s\n" "$id" "$name" "$state" "$time" "$remaining_time" "$extra"
        done <<< "$ACTIVE_JOBS"
    fi

    echo ""

    # --- 2. Recent History ---
    echo "⌛ RECENT HISTORY (Last 24h)"
    # Filtering for main jobs (ignoring .batch/.extern steps)
    HISTORY=$(sacct -u "$USER" -S $(date -d "24 hours ago" +%Y-%m-%dT%H:%M) --format="JobID,JobName%50,State,ExitCode" --noheader | grep "NGS_" | grep -v "\." || true)

    ACTIVE_JOB_IDS=()
    if [ -n "$ACTIVE_JOBS" ]; then
        while IFS='|' read -r id name state time start extra; do
            [ -n "$id" ] && ACTIVE_JOB_IDS+=("$id")
        done <<< "$ACTIVE_JOBS"
    fi

    FILTERED_HISTORY_LINES=()
    while IFS= read -r line; do
        [ -n "${line//[[:space:]]/}" ] || continue

        read -r id name state exitcode <<< "$line"
        [ -n "$id" ] || continue

        SKIP=false
        for active_id in "${ACTIVE_JOB_IDS[@]}"; do
            if [ "$id" = "$active_id" ]; then
                SKIP=true
                break
            fi
        done
        [ "$SKIP" = true ] && continue
        FILTERED_HISTORY_LINES+=("$line")
    done <<< "$HISTORY"

    local total_history=${#FILTERED_HISTORY_LINES[@]}
    if [ "$total_history" -eq 0 ]; then
        echo "    No NGS job history found for the last 24 hours."
    else
        printf "    %-10s %-50s %-15s %-10s\n" "JOBID" "CASE" "STATE" "EXIT"
        local history_count=0
        for line in "${FILTERED_HISTORY_LINES[@]}"; do
            if [ "$history_count" -ge "$max_history_items" ]; then
                local remaining_count=$(( total_history - history_count ))
                echo "    ... and $remaining_count more past job(s)"
                break
            fi

            read -r id name state exitcode <<< "$line"

            # Mark failures with a cross
            STATUS_ICON="❓"
            [[ "$state" == "FAILED"* ]] && STATUS_ICON="❌"
            [[ "$state" == "TIMEOUT"* ]] && STATUS_ICON="❌"
            [[ "$state" == "CANCELLED"* ]] && STATUS_ICON="🛑"
            [[ "$state" == "RUNNING" ]] && STATUS_ICON="⚙️ "
            [[ "$state" == "PENDING"* ]] && STATUS_ICON="⏳"
            [[ "$state" == "COMPLETED"* ]] && STATUS_ICON="✅"

            printf "    %-10s %-50s %-15s %-10s %s\n" "$id" "$name" "$state" "$exitcode" "$STATUS_ICON"
            history_count=$(( history_count + 1 ))
        done
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

    UNIQUE_CASES_ARRAY=()
    while read -r case_id; do
        [ -n "$case_id" ] && UNIQUE_CASES_ARRAY+=("$case_id")
    done < <(printf "%s\n" "${CASES[@]}" 2>/dev/null | grep -v '^$' | sort -u || true)

    local total_cases=${#UNIQUE_CASES_ARRAY[@]}
    if [ "$total_cases" -eq 0 ]; then
        echo "    No log directories found under $RESULTS_BASE"
    else
        printf "    %-46s %-s\n" "CASE ID" "ABSOLUTE LOG PATH"
        local case_count=0
        for case_id in "${UNIQUE_CASES_ARRAY[@]}"; do
            if [ "$case_count" -ge "$max_log_items" ]; then
                local remaining_case_count=$(( total_cases - case_count ))
                echo "    ... and $remaining_case_count more case log path(s)"
                break
            fi
            log_dir="$RESULTS_BASE/$case_id/log"
            abs_path=$(realpath "$log_dir" 2>/dev/null || echo "$log_dir")
            printf "    %-46s %-s\n" "$case_id" "$abs_path"
            case_count=$(( case_count + 1 ))
        done

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