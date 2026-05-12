#!/bin/bash
# setup.sh - Environment setup for NGS Tumor Pipeline
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config/common.sh"

echo "Setting up NGS Tumor Pipeline on $PIPELINE_HOST..."

# 1. Host-specific binary setup
if [ "$PIPELINE_HOST" = "palma" ]; then
    echo "Loading Python module for venv creation..."
    load_modules "$TOOLCHAIN_PYTHON" "$PYTHON_MODULE"
fi

# 2. Virtual Environment Setup
echo "Creating/Updating Python virtual environment at $VENV_PATH..."
if [ ! -d "$VENV_PATH" ]; then
    python3 -m venv "$VENV_PATH"
fi

source "$VENV_PATH/bin/activate"
pip install --upgrade pip
if [ -f "$PROJECT_DIR/requirements.txt" ]; then
    pip install -r "$PROJECT_DIR/requirements.txt"
fi

# 3. Directory Setup
echo "Creating required directories..."
mkdir -p "$INPUT_DIR" "$VARIANTS_SEARCH_DIR" "$RESULTS_BASE"

# 4. Final verification
echo "--------------------------------------------------------------------------------"
echo "Setup complete for $PIPELINE_HOST."
echo "Project Directory: $PROJECT_DIR"
echo "Virtual Env:      $VENV_PATH"
echo "Input FASTQ:      $INPUT_DIR"
echo "Input VCF/JSON:   $VARIANTS_SEARCH_DIR"
echo "Results Base:     $RESULTS_BASE"
echo "--------------------------------------------------------------------------------"
echo "To run the pipeline, use: bash run.sh"
