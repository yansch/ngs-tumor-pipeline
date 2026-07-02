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

echo "-------------------------------------------------------"
echo "🔍 NGS Pipeline Status for user: $USER"
echo "-------------------------------------------------------"

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
    if (( total_seconds < 1800 )); then
        total_seconds=1800
    fi

    elapsed_seconds=$(( $(date +%s) - $(date -d "$start_time" +%s) ))
    remaining_seconds=$(( total_seconds - elapsed_seconds ))

    format_duration "$remaining_seconds"
}

# --- 1. Active Queue Status ---
echo "👩🏼‍🔬  ACTIVE JOBS (squeue)"
ACTIVE_JOBS=$(squeue -u "$USER" -o "%10i %20j %10T %10M %19S %R" --noheader | grep "NGS_" || true)

if [ -z "$ACTIVE_JOBS" ]; then
    echo "    No active NGS jobs found in the queue."
else
    printf "    %-10s %-20s %-10s %-10s %-10s %-s %-s\n" "JOBID" "CASE" "STATE" "TIME" "REMAINING" "NODE/REASON" "OUT LOG"
    while read -r id name state time start extra; do
        remaining_time="N/A"
        out_log="N/A"
        case_label="${name#NGS_}"
        if [ -n "$id" ] && [ -n "$case_label" ]; then
            out_log="tail -f \"$RESULTS_BASE/$case_label/log/${id}_${case_label}_*.out\""
        fi
        if [[ "$state" == "RUNNING" && "$start" != "N/A" && "$start" != "Unknown" ]]; then
            remaining_time=$(estimate_remaining_time "$name" "$start")
        fi
        printf "    %-10s %-20s %-10s %-10s %-10s %-s %-s\n" "$id" "$name" "$state" "$time" "$remaining_time" "$extra" "$out_log"
    done <<< "$ACTIVE_JOBS"
fi

echo ""

# --- 2. Recent History ---
echo "⌛ RECENT HISTORY (Last 24h)"
# Filtering for main jobs (ignoring .batch/.extern steps)
HISTORY=$(sacct -u "$USER" -S $(date -d "24 hours ago" +%Y-%m-%dT%H:%M) --format="JobID,JobName%25,State,ExitCode" --noheader | grep "NGS_" | grep -v "\." || true)

if [ -z "$HISTORY" ]; then
    echo "    No NGS job history found for the last 24 hours."
else
    printf "    %-10s %-25s %-15s %-10s\n" "JOBID" "CASE" "STATE" "EXIT"
    while read -r id name state exitcode; do
        # Mark failures with a cross
        STATUS_ICON="✅"
        [[ "$state" == "FAILED"* ]] && STATUS_ICON="❌"
        [[ "$state" == "TIMEOUT"* ]] && STATUS_ICON="❌"
        [[ "$state" == "CANCELLED"* ]] && STATUS_ICON="🛑"
        [[ "$state" == "RUNNING" ]] && STATUS_ICON="⚙️ "

        printf "    %-10s %-25s %-15s %-10s %s\n" "$id" "$name" "$state" "$exitcode" "$STATUS_ICON"
    done <<< "$HISTORY"
fi

echo ""

# --- 3. Log Inspection Commands ---
echo "📄 LOG ACCESS"
# Get the 3 most recent sample log files to show examples
RECENT_LOGS=$(find "$RESULTS_BASE" -path "*/log/*.out" -type f 2>/dev/null | sort -r | head -n 3 || true)

if [ -z "$RECENT_LOGS" ]; then
    echo "    No log files found under $RESULTS_BASE/*/log"
else
    echo "    To watch a running job:"
    echo "    tail -f $RESULTS_BASE/<CASE>/log/[JOBID]_*.out"
    echo "    tail -f $RESULTS_BASE/<CASE>/log/[JOBID]_*.err"
    echo ""
    echo "    Most recent log files:"
    for log in $RECENT_LOGS; do
        echo "    📂 $(basename "$log")"
    done
fi

echo "-------------------------------------------------------"
echo "💡 Tip: Use 'scancel -u $USER' to stop all your jobs."
echo "-------------------------------------------------------"