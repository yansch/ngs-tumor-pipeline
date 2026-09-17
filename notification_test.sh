#!/usr/bin/env bash
set -euo pipefail

export DISPLAY=:0
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_DIR="${PROJECT_DIR:-$SCRIPT_DIR}"
source "$PROJECT_DIR/config/common.sh"

analysis_gui_start
analysis_gui_update title "Analysis progress (11 cases)"

total_cases=3

for ((case_num=1; case_num<=total_cases; case_num++)); do
    # Per-case progress 0?100
    for pct in $(seq 0 5 100); do
        # Overall progress: how many full cases done + fraction of current
        # Cases fully done: case_num - 1
        # Fraction of current case: pct / 100
        overall_pct=$(awk -v c="$case_num" -v p="$pct" -v n="$total_cases" \
            'BEGIN { printf "%.0f", ((c - 1) + p / 100.0) * 100.0 / n }')
        analysis_gui_update overall "$overall_pct" "Overall: $overall_pct% (case $case_num/$total_cases)"
        analysis_gui_update case "$pct" "Case $case_num: $pct%"
        sleep 0.5
    done
done

analysis_gui_update overall 100 "All cases complete."
analysis_gui_update case 100 "Done."
sleep 2
analysis_gui_stop