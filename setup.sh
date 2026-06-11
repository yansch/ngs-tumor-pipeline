#!/bin/bash
# setup.sh - Environment setup for NGS Tumor Pipeline
set -eo pipefail

# --- 0. Configuration & Setup ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config/common.sh"

ENV_FILE="$PROJECT_DIR/.env"
CURRENT_ONCOKB_TOKEN="${ONCOKB_API_TOKEN:-}"

if [ -n "$CURRENT_ONCOKB_TOKEN" ]; then
    printf '🔑 OncoKB token is already configured. Enter a new token to replace it, or press Enter to keep it: '
else
    printf '🔑 Enter your OncoKB API token (or press Enter to skip): '
fi

read -r -s ONCOKB_TOKEN_INPUT || true
echo

if [ -n "$ONCOKB_TOKEN_INPUT" ]; then
    ONCOKB_API_TOKEN="$ONCOKB_TOKEN_INPUT"
    if [ -f "$ENV_FILE" ]; then
        tmp_env_file="$(mktemp)"
        grep -v '^ONCOKB_API_TOKEN=' "$ENV_FILE" > "$tmp_env_file" || true
        printf 'ONCOKB_API_TOKEN=%s\n' "$ONCOKB_API_TOKEN" >> "$tmp_env_file"
        mv "$tmp_env_file" "$ENV_FILE"
    else
        printf 'ONCOKB_API_TOKEN=%s\n' "$ONCOKB_API_TOKEN" > "$ENV_FILE"
    fi
    chmod 600 "$ENV_FILE" 2>/dev/null || true
    echo "✅ Saved OncoKB token to $ENV_FILE"
elif [ -n "$CURRENT_ONCOKB_TOKEN" ]; then
    echo "Keeping existing OncoKB token."
else
    echo "Skipping OncoKB token setup. You can rerun setup.sh later to add it."
fi

echo "-------------------------------------------------------"
echo "🚀 Setting up NGS Tumor Pipeline on $PIPELINE_HOST"
echo "-------------------------------------------------------"

# --- 1. Python Binary Selection ---
# Identify the best Python version (Mirroring Cluster 3.11)
if [ "$PIPELINE_HOST" = "palma" ]; then
    echo "📦 [Cluster] Loading Python modules..."
    load_modules "$ANALYSIS_TOOLCHAIN_MODULE" "${PYTHON_MODULES[@]}"
    PY_BIN="python3"
elif command -v python3.11 >/dev/null 2>&1; then
    echo "✅ [Local] Found Python 3.11 (Recommended)"
    PY_BIN="python3.11"
else
    echo "⚠️  [Local] Python 3.11 not found. Using system python3."
    PY_BIN="python3"
fi

# Check version for user peace of mind
ACTUAL_VER=$($PY_BIN -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
echo "🛠️  Using Python $ACTUAL_VER from $(command -v $PY_BIN)"

# --- 2. Virtual Environment Management ---
if [ ! -d "$VENV_PATH" ]; then
    echo "🌱 Creating new virtual environment at $VENV_PATH..."
    $PY_BIN -m venv "$VENV_PATH"
else
    echo "🔄 Existing environment found. Refreshing dependencies..."
fi

source "$VENV_PATH/bin/activate"

export PIP_CACHE_DIR="$SCRATCH_DIR/.pip_cache"
mkdir -p "$PIP_CACHE_DIR"

# Optimization: Parallel installs and cache usage
echo "pip: Upgrading core tools..."
pip install --quiet --upgrade pip setuptools wheel

if [ -f "$PROJECT_DIR/requirements.txt" ]; then
    echo "pip: Installing pipeline requirements..."
    pip install -r "$PROJECT_DIR/requirements.txt"
fi

if [[ "$PIPELINE_HOST" == "omen" ]]; then
    if command -v bwa-mem2 >/dev/null 2>&1; then
        echo "✅ BWA-MEM2 already available: $(which bwa-mem2)"
    else
        echo "📥 Installing BWA-MEM2 locally (Omen)..."

        tmp_dir="$(mktemp -d)"
        (
            set -e
            cd "$tmp_dir"
            # Cloning the bwa-mem2 repository with submodules (it requires them for safe compilation)
            git clone --recursive https://github.com/bwa-mem2/bwa-mem2.git
            cd bwa-mem2
            
            # Compile. Note: 'make' automatically optimizes for Omen's specific CPU architecture
            make
            
            # Copy the compiled binary into the venv bin directory
            cp bwa-mem2* "$VENV_PATH/bin/"
        )
        rm -rf "$tmp_dir"

        echo "✅ BWA-MEM2 installed into venv bin"
    fi
fi

# --- 3. Directory Infrastructure ---
echo "📂 Initializing project directories..."
mkdir -p "$INPUT_DIR" "$VARIANTS_SEARCH_DIR" "$RESULTS_BASE"

# --- 4. Final Verification ---
echo "-------------------------------------------------------"
echo "✨ Setup complete for $PIPELINE_HOST."
echo "   Project: $PROJECT_DIR"
echo "   Python:  $(python --version) inside $VENV_PATH"
echo "-------------------------------------------------------"
echo "To begin, run: bash run.sh"