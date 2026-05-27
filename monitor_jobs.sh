#!/bin/bash
# status.sh - Monitor NGS Pipeline jobs and logs
set -eo pipefail

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config/common.sh"

echo "-------------------------------------------------------"
echo "🔍 NGS Pipeline Status for user: $USER"
echo "-------------------------------------------------------"

# --- 1. Active Queue Status ---
echo "▶️  ACTIVE JOBS (squeue)"
ACTIVE_JOBS=$(squeue -u "$USER" -o "%10i %20j %10T %10M %R" --noheader | grep "NGS_" || true)

if [ -z "$ACTIVE_JOBS" ]; then
    echo "    No active NGS jobs found in the queue."
else
    printf "    %-10s %-20s %-10s %-10s %-s\n" "JOBID" "CASE" "STATE" "TIME" "NODE/REASON"
    while read -r id name state time extra; do
        printf "    %-10s %-20s %-10s %-10s %-s\n" "$id" "$name" "$state" "$time" "$extra"
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
        [[ "$state" == "CANCELLED"* ]] && STATUS_ICON="🛑"
        [[ "$state" == "RUNNING" ]] && STATUS_ICON="⚙️ "

        printf "    %-10s %-25s %-15s %-10s %s\n" "$id" "$name" "$state" "$exitcode" "$STATUS_ICON"
    done <<< "$HISTORY"
fi

echo ""

# --- 3. Log Inspection Commands ---
echo "📄 LOG ACCESS"
# Get the 3 most recent log files to show examples
RECENT_LOGS=$(ls -t "$SCRATCH_DIR/slurm_logs"/*.out 2>/dev/null | head -n 3 || true)

if [ -z "$RECENT_LOGS" ]; then
    echo "    No log files found in $SCRATCH_DIR/slurm_logs"
else
    echo "    To watch a running job:"
    echo "    tail -f $SCRATCH_DIR/slurm_logs/[JOBID]_*.out"
    echo "    tail -f $SCRATCH_DIR/slurm_logs/[JOBID]_*.err"
    echo ""
    echo "    Most recent log files:"
    for log in $RECENT_LOGS; do
        echo "    📂 $(basename "$log")"
    done
fi

echo "-------------------------------------------------------"
echo "💡 Tip: Use 'scancel -u $USER' to stop all your jobs."
echo "-------------------------------------------------------"