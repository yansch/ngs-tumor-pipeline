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
unset __NGS_PRESERVED_VALUES

export MPLBACKEND=Agg

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

load_ngs_python_env() {
    if [ -f "$VENV_PATH/bin/activate" ]; then
        source "$VENV_PATH/bin/activate"
    else
        echo "❌ Error: Virtual environment not found at $VENV_PATH. Run setup.sh first."
        exit 1
    fi
}