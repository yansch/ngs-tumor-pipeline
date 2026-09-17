#!/bin/bash
# config/common.sh - Host detection and shared logic

# 1. Path Management
# Get the directory where THIS script lives (the config folder)
CONF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The project root is one level up
export PROJECT_DIR="$(dirname "$CONF_DIR")"

# Preserve run-time --set overrides across host config sourcing.
declare -A __NGS_PRESERVED_VALUES=()
if [[ -n "${NGS_CONFIG_PRESERVE_VARS:-}" ]]; then
    IFS=',' read -r -a __NGS_PRESERVE_LIST <<< "$NGS_CONFIG_PRESERVE_VARS"
    for __ngs_var in "${__NGS_PRESERVE_LIST[@]}"; do
        [[ -z "$__ngs_var" ]] && continue
        if [[ -v $__ngs_var ]]; then
            __NGS_PRESERVED_VALUES["$__ngs_var"]="${!__ngs_var}"
        fi
    done
fi

# 2. Host Detection
HOSTNAME_S=$(hostname -s)
if [[ "$HOSTNAME_S" == palma* || "$HOSTNAME_S" == r* ]]; then
    export PIPELINE_HOST="palma"
else
    export PIPELINE_HOST="omen"
fi

# 3. Source host-specific configuration
# We use CONF_DIR here because omen.sh/palma.sh are in the same folder
if [ -f "$CONF_DIR/${PIPELINE_HOST}.sh" ]; then
    source "$CONF_DIR/${PIPELINE_HOST}.sh"
else
    echo "❌ Error: Configuration for host $PIPELINE_HOST not found in $CONF_DIR"
    exit 1
fi

# Load local project overrides, if present.
if [[ -f "$PROJECT_DIR/.env" ]]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

# Load optional external overrides file, if requested.
if [[ -n "${NGS_CONFIG_OVERRIDES_FILE:-}" ]]; then
    if [[ -f "$NGS_CONFIG_OVERRIDES_FILE" ]]; then
        set -a
        source "$NGS_CONFIG_OVERRIDES_FILE"
        set +a
    else
        echo "❌ Error: NGS_CONFIG_OVERRIDES_FILE not found: $NGS_CONFIG_OVERRIDES_FILE"
        exit 1
    fi
fi

# Re-apply --set values so they stay highest precedence.
for __ngs_var in "${!__NGS_PRESERVED_VALUES[@]}"; do
    export "$__ngs_var=${__NGS_PRESERVED_VALUES[$__ngs_var]}"
done

unset __ngs_var
unset __NGS_PRESERVE_LIST
export MPLBACKEND=Agg

# --- Load Status Tracker ---
if [ -f "$PROJECT_DIR/lib/status_tracker.sh" ]; then
    source "$PROJECT_DIR/lib/status_tracker.sh"
fi

# --- Helper Functions ---

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
    [ "$HAS_MODULE_SYSTEM" = true ] && module purge || true
}

test_python_env_path() {
    local setup="${1:-false}"
       
    #Normalize the default path and the actual path.
    #env location according to host config
    CONFIG_VENV_PATH="$(realpath -m -- "$VENV_PATH")"
    #where the location is expected depending on our actual path
    ACTUAL_VENV_PATH="$(realpath -m -- "$PROJECT_DIR/env")"

    if [[ "$CONFIG_VENV_PATH" != "$ACTUAL_VENV_PATH" ]]; then
        printf '⚠️ configured default environment path differs from actual path.\n' >&2
        printf 'Default: %s\n' "$CONFIG_VENV_PATH" >&2
        printf 'Actual: %s\n' "$ACTUAL_VENV_PATH" >&2

        # Use the path based on the actual project path.
        VENV_PATH="$ACTUAL_VENV_PATH"
        printf 'Using environment path at %s\n' "$VENV_PATH"
    else
        # Use the normalized path from the configuration, dont say anything because this is normal.
        VENV_PATH="$CONFIG_VENV_PATH"
    fi

    #check for environment, dont fail if setup is executed (gets a true on function call as argument)
    if [[ ! -f "$VENV_PATH/bin/activate" && "$setup" == "false" ]]; then
        echo "❌ Error: Virtual environment not found at $VENV_PATH. Run setup.sh first."
        exit 1
    fi
}


load_ngs_python_env() {
    if [ -f "$VENV_PATH/bin/activate" ]; then
        source "$VENV_PATH/bin/activate"
    else
        echo "❌ Error: Virtual environment not found at $VENV_PATH. Run setup.sh first."
        exit 1
    fi
}

# --- UI & Update Helpers ---

# Layout helper (defaults to '-', takes any character; adjusts dynamically to terminal width)
layout() {
    local width char
    width=$(tput cols 2>/dev/null || echo 80)
    char=${1:--}
    printf "%${width}s\n" | tr ' ' "$char"
}

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
        # show $behind amount of commit messages:
        if [ "$BEHIND" -gt 10 ];then
            echo "Update Messages (showing 10 of $BEHIND)"
            git log -10 --format="%h %s" origin/main #showing more breaks the terminal
        else
            echo "Update Messages"
            git log -"$BEHIND" --format="%h %s" origin/main
        fi
        layout '='

        echo -e "\n⚠️  WARNING: Updating will discard any local changes that you made to the pipeline."
        echo "   If you have not changed any code here, you can safely proceed."
        read -rp "Do you want to update now? [y/n] " answer
        case "${answer,,}" in
            y|yes)
                echo "Updating repository to origin/main..."
                git reset --hard origin/main
                git pull
                echo "✅ Pipeline updated successfully. Please re-run your command."
                exit 0
                ;;
            *)
                echo "Skipping update."
                ;;
        esac
    else
        echo -e "✅ Pipeline is up to date!\n"
    fi
}