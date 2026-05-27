#!/bin/bash
# setup.sh - Environment setup for NGS Tumor Pipeline
set -eo pipefail

# --- 0. Configuration & Setup ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config/common.sh"

echo "-------------------------------------------------------"
echo "🚀 Setting up NGS Tumor Pipeline on $PIPELINE_HOST"
echo "-------------------------------------------------------"

# --- 1. Python Binary Selection ---
# Identify the best Python version (Mirroring Cluster 3.11)
if [ "$PIPELINE_HOST" = "palma" ]; then
    echo "📦 [Cluster] Loading Python modules..."
    load_modules "$TOOLCHAIN_PYTHON" "$PYTHON_MODULE"
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