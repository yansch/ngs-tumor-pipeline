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

# ---------------------------------------------------------------------------
# Module Helpers
#   load_modules MOD [MOD ...]  — load environment modules if available
#   purge_modules               — purge all loaded modules
# ---------------------------------------------------------------------------
load_modules() {
    if [ "$HAS_MODULE_SYSTEM" = true ]; then
        for mod in "$@"; do
            [ -z "$mod" ] && continue
            module load "$mod"
        done
    fi
    return 0
}

purge_modules() {
    if [ "$HAS_MODULE_SYSTEM" = true ]; then
        module purge
    fi
}

# ---------------------------------------------------------------------------
# Python Environment Helpers
# ---------------------------------------------------------------------------

# test_python_env_path [setup]
#   Validates and normalises $VENV_PATH against the actual project location.
#   Pass "true" as first arg when called from setup.sh (skips the missing-env check).
test_python_env_path() {
    local setup="${1:-false}"

    # Normalise both the configured path and the path derived from $PROJECT_DIR.
    CONFIG_VENV_PATH="$(realpath -m -- "$VENV_PATH")"
    ACTUAL_VENV_PATH="$(realpath -m -- "$PROJECT_DIR/env")"

    if [[ "$CONFIG_VENV_PATH" != "$ACTUAL_VENV_PATH" ]]; then
        printf '⚠️ configured default environment path differs from actual path.\n' >&2
        printf 'Default: %s\n' "$CONFIG_VENV_PATH" >&2
        printf 'Actual: %s\n' "$ACTUAL_VENV_PATH" >&2
        # Use the path based on the actual project location.
        VENV_PATH="$ACTUAL_VENV_PATH"
        printf 'Using environment path at %s\n' "$VENV_PATH"
    else
        # Normalised path matches — use it silently.
        VENV_PATH="$CONFIG_VENV_PATH"
    fi

    # Skip the existence check when called from setup.sh (env not created yet).
    if [[ ! -f "$VENV_PATH/bin/activate" && "$setup" == "false" ]]; then
        echo "❌ Error: Virtual environment not found at $VENV_PATH. Run setup.sh first."
        exit 1
    fi
}

# load_ngs_python_env
#   Activates the project virtual environment. Exits on failure.
load_ngs_python_env() {
    if [ -f "$VENV_PATH/bin/activate" ]; then
        source "$VENV_PATH/bin/activate"
    else
        echo "❌ Error: Virtual environment not found at $VENV_PATH. Run setup.sh first."
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# UI & Update Helpers
# ---------------------------------------------------------------------------

# layout [char]
#   Prints a full-width horizontal rule using char (default: '-').
layout() {
    local width char
    width=$(tput cols 2>/dev/null || echo 80)
    char=${1:--}
    printf "%${width}s\n" | tr ' ' "$char"
}

# update_check
#   Fetches origin/main and, when behind, offers an interactive update prompt.
#   Skips automatically in non-interactive (non-tty) environments.
update_check() {
    # Only run in interactive terminal
    if [ ! -t 0 ]; then
        return 0
    fi

    echo "🔍 Checking for updates from origin/main..."
    git fetch --quiet 2>/dev/null || true
    local BEHIND
    BEHIND=$(git rev-list --count HEAD..origin/main 2>/dev/null || echo 0)

    if [ "$BEHIND" -gt 0 ]; then
        if [ "$BEHIND" -eq 1 ]; then
            echo -e "\n📦 There is $BEHIND new update available."
        else
            echo -e "\n📦 There are $BEHIND new updates available."
        fi
        if [ "$BEHIND" -lt 5 ]; then
            echo "   Consider updating."
        else
            echo "   Your pipeline version is outdated. Please update!"
        fi

        layout '='
        if [ "$BEHIND" -gt 10 ]; then
            echo "Update Messages (showing 10 of $BEHIND)"
            git log -10 --format="%h %s" origin/main
        else
            echo "Update Messages"
            git log -"$BEHIND" --format="%h %s" origin/main
        fi
        layout '='

        read -rp "Do you want to update now? [y/n] " answer
        case "${answer,,}" in
            y|yes)
                echo "Updating repository to origin/main..."
                if git pull --ff-only; then
                    echo "✅ Pipeline updated successfully. Please re-run your command."
                    exit 0
                else
                    echo "❌ Update failed: local branch has diverged from origin/main."
                    echo "   Please resolve manually with 'git pull' or 'git rebase origin/main'."
                    exit 1
                fi
                ;;
            *)
                echo "Skipping update."
                ;;
        esac
    else
        echo -e "✅ Pipeline is up to date!\n"
    fi
}
