#!/bin/bash
# lib/common_functions.sh - Shared utilities for NGS pipeline component scripts
# Sourced by each component in components/*/run_*.sh
# Requires: PROJECT_DIR, LOG_DIR to be set by the orchestrator.

# ---------------------------------------------------------------------------
# step_start "Step Name"
#   Prints a timestamped banner at the beginning of a step.
# ---------------------------------------------------------------------------
step_start() {
    local name="$1"
    echo ""
    echo "▶ [$(date '+%H:%M:%S')] ${name}"
    echo "─────────────────────────────────────────────────────────────────────"
}

# ---------------------------------------------------------------------------
# step_end "Step Name" [start_epoch]
#   Prints a completion message. If start_epoch is given, also prints duration.
# ---------------------------------------------------------------------------
step_end() {
    local name="$1"
    local t0="${2:-}"
    if [ -n "$t0" ]; then
        local elapsed=$(( $(date +%s) - t0 ))
        printf "✅ %s — done in %02d:%02d:%02d\n" \
            "$name" \
            $(( elapsed/3600 )) $(( (elapsed%3600)/60 )) $(( elapsed%60 ))
    else
        echo "✅ ${name} — done"
    fi
}

# ---------------------------------------------------------------------------
# run_if_missing "$output_file" "human-readable description"
#   Returns 0 if the file is missing (caller should run the step).
#   Returns 1 if the file already exists (caller should skip).
#
# Usage pattern:
#   if run_if_missing "$OUT_FILE" "fastp trimming"; then
#       fastp ...
#   fi
# ---------------------------------------------------------------------------
run_if_missing() {
    local output_file="$1"
    local description="${2:-step}"
    if [ -e "$output_file" ]; then
        echo "   ⏭  Skipping ${description} — output already exists: $(basename "$output_file")"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# require_vars VAR1 VAR2 ...
#   Checks that each named variable is non-empty. Exits 1 with a clear error
#   message if any are missing.
# ---------------------------------------------------------------------------
require_vars() {
    local missing=()
    for var in "$@"; do
        if [ -z "${!var:-}" ]; then
            missing+=("$var")
        fi
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        echo "❌ Missing required environment variables: ${missing[*]}" >&2
        echo "   Check your config files and orchestrator path setup." >&2
        exit 1
    fi
}
