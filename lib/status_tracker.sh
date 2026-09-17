#!/bin/bash
# lib/status_tracker.sh - Non-blocking status reporting and desktop notifications
#
# Writes decoupled status updates to /tmp/ngs_pipeline_status.json
# All functions are fail-safe and will NEVER cause the pipeline to fail.

export NGS_STATUS_FILE="${NGS_STATUS_FILE:-/tmp/ngs_pipeline_status.json}"
export DISPLAY="${DISPLAY:-:0}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/1000/bus}"

# Internal atomic JSON writer
_write_status_json() {
    local json="$1"
    local tmp_file="${NGS_STATUS_FILE}.tmp.$$"
    (
        printf '%s\n' "$json" > "$tmp_file" && mv -f "$tmp_file" "$NGS_STATUS_FILE"
    ) 2>/dev/null || true
}

# Send desktop notification safely
status_notify() {
    local title="${1:-NGS Pipeline}"
    local message="${2:-}"
    local urgency="${3:-normal}"   # low, normal, critical
    local icon="${4:-dialog-information}"

    if command -v notify-send &>/dev/null; then
        (
            export DISPLAY="${DISPLAY:-:0}"
            export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/1000/bus}"
            notify-send -u "$urgency" -i "$icon" "$title" "$message"
        ) &>/dev/null &
    fi
    return 0
}

# Initialize status at the beginning of run.sh
status_init() {
    local total_cases="${1:-0}"
    local input_dir="${2:-}"
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')

    local json
    json=$(cat <<EOF
{
  "running": true,
  "pid": $$,
  "host": "${PIPELINE_HOST:-unknown}",
  "total_cases": $total_cases,
  "cases_completed": 0,
  "case_index": 0,
  "case_label": "",
  "step_name": "Initializing...",
  "step_status": "starting",
  "overall_percent": 0,
  "case_percent": 0,
  "start_time": "$now",
  "last_update": "$now",
  "message": "Pipeline started with $total_cases case(s)."
}
EOF
)
    _write_status_json "$json"

    if [ "${PIPELINE_HOST:-}" = "omen" ]; then
        status_notify "🧬 NGS Pipeline Started" "Processing $total_cases case(s). Please leave the laptop powered on." "critical" "system-run"
    fi
}

# Update when starting a specific case in the loop
status_case_start() {
    local case_label="${1:-}"
    local case_idx="${2:-1}"
    local total_cases="${3:-1}"
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')

    local overall_pct=0
    if [ "$total_cases" -gt 0 ]; then
        overall_pct=$(( ((case_idx - 1) * 100) / total_cases ))
    fi

    local json
    json=$(cat <<EOF
{
  "running": true,
  "pid": $$,
  "host": "${PIPELINE_HOST:-unknown}",
  "total_cases": $total_cases,
  "cases_completed": $((case_idx - 1)),
  "case_index": $case_idx,
  "case_label": "$case_label",
  "step_name": "Starting case analysis...",
  "step_status": "running",
  "overall_percent": $overall_pct,
  "case_percent": 0,
  "start_time": "${now}",
  "last_update": "$now",
  "message": "Processing case $case_idx of $total_cases: $case_label"
}
EOF
)
    _write_status_json "$json"
}

# Update when a component step starts or finishes
status_step_update() {
    local step_name="${1:-}"
    local step_status="${2:-running}"  # running or done
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')

    # Read existing metadata if available
    local total_cases=1 case_idx=1 cases_completed=0 case_label=""
    if [ -f "$NGS_STATUS_FILE" ] && command -v jq &>/dev/null; then
        total_cases=$(jq -r '.total_cases // 1' "$NGS_STATUS_FILE" 2>/dev/null || echo 1)
        case_idx=$(jq -r '.case_index // 1' "$NGS_STATUS_FILE" 2>/dev/null || echo 1)
        cases_completed=$(jq -r '.cases_completed // 0' "$NGS_STATUS_FILE" 2>/dev/null || echo 0)
        case_label=$(jq -r '.case_label // ""' "$NGS_STATUS_FILE" 2>/dev/null || echo "")
    fi

    # Estimate step progress (1-9) based on step string prefix
    local step_num=1
    if [[ "$step_name" =~ ^([0-9]+) ]]; then
        step_num=$(( 10#${BASH_REMATCH[1]} ))
    fi
    local total_steps=9
    local case_pct=$(( (step_num * 100) / total_steps ))
    if [ "$case_pct" -gt 100 ]; then case_pct=100; fi

    local overall_pct=0
    if [ "$total_cases" -gt 0 ]; then
        overall_pct=$(( (((case_idx - 1) * 100) + (case_pct / total_cases)) ))
        if [ "$overall_pct" -gt 100 ]; then overall_pct=100; fi
    fi

    local json
    json=$(cat <<EOF
{
  "running": true,
  "pid": $$,
  "host": "${PIPELINE_HOST:-unknown}",
  "total_cases": $total_cases,
  "cases_completed": $cases_completed,
  "case_index": $case_idx,
  "case_label": "${CASE_LABEL:-$case_label}",
  "step_name": "$step_name",
  "step_status": "$step_status",
  "overall_percent": $overall_pct,
  "case_percent": $case_pct,
  "last_update": "$now",
  "message": "Case ${CASE_LABEL:-$case_label}: $step_name ($step_status)"
}
EOF
)
    _write_status_json "$json"
}

# Call at the end of run.sh
status_finish() {
    local total_submitted="${1:-0}"
    local exit_code="${2:-0}"
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')

    local msg="Analysis finished successfully for $total_submitted case(s)."
    local notif_title="✅ NGS Pipeline Complete"
    local notif_urgency="normal"
    local notif_icon="dialog-information"

    if [ "$exit_code" -ne 0 ]; then
        msg="Pipeline encountered an error (exit code $exit_code)."
        notif_title="❌ NGS Pipeline Failed"
        notif_urgency="critical"
        notif_icon="dialog-error"
    fi

    local json
    json=$(cat <<EOF
{
  "running": false,
  "pid": null,
  "host": "${PIPELINE_HOST:-unknown}",
  "total_cases": $total_submitted,
  "cases_completed": $total_submitted,
  "case_index": $total_submitted,
  "case_label": "",
  "step_name": "Completed",
  "step_status": "done",
  "overall_percent": 100,
  "case_percent": 100,
  "last_update": "$now",
  "exit_code": $exit_code,
  "message": "$msg"
}
EOF
)
    _write_status_json "$json"

    if [ "${PIPELINE_HOST:-}" = "omen" ]; then
        status_notify "$notif_title" "$msg" "$notif_urgency" "$notif_icon"
    fi
}

# Launch GUI asynchronously in a completely detached subshell
status_gui_start() {
    local gui_script="$PROJECT_DIR/lib/pipeline_status_gui.py"
    if [ -f "$gui_script" ]; then
        (
            export DISPLAY="${DISPLAY:-:0}"
            export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/1000/bus}"
            # Only start if not already running
            if ! pgrep -f "pipeline_status_gui.py" &>/dev/null; then
                nohup python3 "$gui_script" &>/dev/null &
            fi
        ) 2>/dev/null || true
    fi
}

status_gui_stop() {
    pkill -f "pipeline_status_gui.py" 2>/dev/null || true
}

