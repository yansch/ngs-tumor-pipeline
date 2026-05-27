#!/bin/bash
# config/common.sh - Host detection and shared logic

# 1. Path Management
# Get the directory where THIS script lives (the config folder)
CONF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The project root is one level up
export PROJECT_DIR="$(dirname "$CONF_DIR")"

# Load local environment overrides, if present.
if [[ -f "$PROJECT_DIR/.env" ]]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
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

# --- Helper Functions ---

load_modules() {
    if [ "$HAS_MODULE_SYSTEM" = true ]; then
        # Remove quotes from $@ to allow word splitting
        for mod in $@; do
            [ -z "$mod" ] && continue
            module load "$mod"
        done
    fi
    return 0
}

purge_modules() {
    [ "$HAS_MODULE_SYSTEM" = true ] && module purge || true
}

load_ngs_python_env() {
    if [ -f "$VENV_PATH/bin/activate" ]; then
        source "$VENV_PATH/bin/activate"
    else
        echo "❌ Error: Virtual environment not found at $VENV_PATH. Run setup.sh first."
        exit 1
    fi
}