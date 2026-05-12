#!/bin/bash
# config/common.sh - Host detection and shared logic for NGS Tumor Pipeline

# Detect host
HOSTNAME_S=$(hostname -s)
if [[ "$HOSTNAME_S" == palma* || "$HOSTNAME_S" == r* ]]; then
    export PIPELINE_HOST="palma"
else
    # Assuming Omen if not on Palma
    export PIPELINE_HOST="omen"
fi

# Base directory setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Source host-specific configuration
if [ -f "$SCRIPT_DIR/${PIPELINE_HOST}.sh" ]; then
    source "$SCRIPT_DIR/${PIPELINE_HOST}.sh"
else
    echo "Error: Configuration for host $PIPELINE_HOST not found in $SCRIPT_DIR"
    exit 1
fi

# --- Helper Functions ---

# Module system wrappers — no-ops on hosts without modules
load_modules() {
    if [ "$HAS_MODULE_SYSTEM" = true ]; then
        for mod in "$@"; do
            [ -z "$mod" ] && continue
            module load $mod
        done
    fi
}

purge_modules() {
    if [ "$HAS_MODULE_SYSTEM" = true ]; then
        module purge
    fi
}

# Python venv activation
load_ngs_python_env() {
    if [ -f "$VENV_PATH/bin/activate" ]; then
        source "$VENV_PATH/bin/activate"
    else
        echo "Error: Virtual environment not found at $VENV_PATH. Run setup.sh first."
        exit 1
    fi
}
