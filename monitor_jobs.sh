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

    # --- 1. Collect Active Queue Status ---
    ACTIVE_JOBS=$(squeue -u "$USER" -o "%i|%j|%T|%M|%S|%R" --noheader | grep "NGS_" || true)

    ACTIVE_JOB_IDS=()
    local total_active=0
    if [ -n "$ACTIVE_JOBS" ]; then
        while IFS='|' read -r id name state time start extra; do
            if [ -n "$id" ]; then
                ACTIVE_JOB_IDS+=("$id")
                total_active=$(( total_active + 1 ))
            fi
        done <<< "$ACTIVE_JOBS"
    fi

    # --- 2. Collect Recent History ---
    HISTORY=$(sacct -u "$USER" -S $(date -d "24 hours ago" +%Y-%m-%dT%H:%M) --format="JobID,JobName%50,State,ExitCode" --noheader | grep "NGS_" | grep -v "\." || true)

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

    # --- 3. Collect Log Directories ---
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

    # --- 4. Dynamic Line & Layout Budget Calculation ---
    # Header: 3 lines
    # Footer: 4 lines (if loop) or 3 lines (if --once)
    # Active section overhead: 3 lines (title + table header / empty msg + blank line)
    # History section overhead: 3 lines (title + table header / empty msg + blank line)
    # Log Access overhead: 5 lines (title + table header + blank line + 2 instruction lines) if total_cases > 0, else 2 lines
    # Safety buffer: 1 line

    local header_lines=3
    local footer_lines=4
    [ "$ONCE" = true ] && footer_lines=3

    local active_base=3
    local history_base=3
    local log_base=2
    [ "$total_cases" -gt 0 ] && log_base=5

    local fixed_overhead=$(( header_lines + footer_lines + active_base + history_base + log_base + 1 ))
    local avail_rows=$(( term_lines - fixed_overhead ))
    [ "$avail_rows" -lt 2 ] && avail_rows=2

    # Allocate active jobs
    local max_active_items=$total_active
    if [ "$total_active" -gt 0 ] && [ "$avail_rows" -gt 2 ]; then
        local max_active_cap=$(( avail_rows / 2 ))
        [ "$max_active_cap" -lt 1 ] && max_active_cap=1
        if [ "$total_active" -gt "$max_active_cap" ]; then
            max_active_items=$(( max_active_cap - 1 ))
            [ "$max_active_items" -lt 1 ] && max_active_items=1
            avail_rows=$(( avail_rows - max_active_items - 1 )) # 1 line for overflow note
        else
            avail_rows=$(( avail_rows - total_active ))
        fi
    fi

    [ "$avail_rows" -lt 1 ] && avail_rows=1

    # Allocate remaining rows between History and Log Access
    local max_history_items=0
    local max_log_items=0

    if [ "$total_history" -eq 0 ] && [ "$total_cases" -eq 0 ]; then
        max_history_items=0
        max_log_items=0
    elif [ "$total_history" -eq 0 ]; then
        if [ "$total_cases" -le "$avail_rows" ]; then
            max_log_items=$total_cases
        else
            max_log_items=$(( avail_rows - 1 )) # 1 line for overflow note
            [ "$max_log_items" -lt 1 ] && max_log_items=1
        fi
    elif [ "$total_cases" -eq 0 ]; then
        if [ "$total_history" -le "$avail_rows" ]; then
            max_history_items=$total_history
        else
            max_history_items=$(( avail_rows - 1 )) # 1 line for overflow note
            [ "$max_history_items" -lt 1 ] && max_history_items=1
        fi
    else
        # Both history and cases exist
        if [ $(( total_history + total_cases )) -le "$avail_rows" ]; then
            max_history_items=$total_history
            max_log_items=$total_cases
        else
            local half_1=$(( avail_rows / 2 ))
            local half_2=$(( avail_rows - half_1 ))
            [ "$half_1" -lt 1 ] && half_1=1
            [ "$half_2" -lt 1 ] && half_2=1

            if [ "$total_history" -le "$half_1" ]; then
                max_history_items=$total_history
                local rem_for_logs=$(( avail_rows - max_history_items ))
                if [ "$total_cases" -le "$rem_for_logs" ]; then
                    max_log_items=$total_cases
                else
                    max_log_items=$(( rem_for_logs - 1 ))
                    [ "$max_log_items" -lt 1 ] && max_log_items=1
                fi
            elif [ "$total_cases" -le "$half_2" ]; then
                max_log_items=$total_cases
                local rem_for_hist=$(( avail_rows - max_log_items ))
                if [ "$total_history" -le "$rem_for_hist" ]; then
                    max_history_items=$total_history
                else
                    max_history_items=$(( rem_for_hist - 1 ))
                    [ "$max_history_items" -lt 1 ] && max_history_items=1
                fi
            else
                # Both exceed their share
                max_history_items=$(( half_1 - 1 ))
                max_log_items=$(( half_2 - 1 ))
                [ "$max_history_items" -lt 1 ] && max_history_items=1
                [ "$max_log_items" -lt 1 ] && max_log_items=1
            fi
        fi
    fi

    # --- 5. Render Screen Output ---
    echo "-------------------------------------------------------"
    echo "🔍 NGS Pipeline Status for user: $USER"
    echo "-------------------------------------------------------"

    echo "👩🏼‍🔬  ACTIVE JOBS (squeue)"
    if [ "$total_active" -eq 0 ]; then
        echo "    No active NGS jobs found in the queue."
    else
        printf "    %-10s %-50s %-10s %-10s %-10s %-s\n" "JOBID" "CASE" "STATE" "TIME" "REMAINING" "NODE/REASON"
        local active_count=0
        while IFS='|' read -r id name state time start extra; do
            [ -n "$id" ] || continue
            if [ "$active_count" -ge "$max_active_items" ]; then
                local remaining_active_count=$(( total_active - active_count ))
                echo "    ... and $remaining_active_count more active job(s)"
                break
            fi
            remaining_time="N/A"
            if [[ "$state" == "RUNNING" && "$start" != "N/A" && "$start" != "Unknown" ]]; then
                remaining_time=$(estimate_remaining_time "$name" "$start")
            fi
            printf "    %-10s %-50s %-10s %-10s %-10s %-s\n" "$id" "$name" "$state" "$time" "$remaining_time" "$extra"
            active_count=$(( active_count + 1 ))
        done <<< "$ACTIVE_JOBS"
    fi

    echo ""

    echo "⌛ RECENT HISTORY (Last 24h)"
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

    echo "📄 LOG ACCESS"
    if [ "$total_cases" -eq 0 ]; then
        echo "    No log directories found under $RESULTS_BASE"
    else
        printf "    %-32s %-s\n" "CASE ID" "ABSOLUTE LOG PATH"
        local case_count=0
        for case_id in "${UNIQUE_CASES_ARRAY[@]}"; do
            if [ "$case_count" -ge "$max_log_items" ]; then
                local remaining_case_count=$(( total_cases - case_count ))
                echo "    ... and $remaining_case_count more case log path(s)"
                break
            fi
            log_dir="$RESULTS_BASE/$case_id/log"
            abs_path=$(realpath "$log_dir" 2>/dev/null || echo "$log_dir")
            printf "    %-32s %-s\n" "$case_id" "$abs_path"
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