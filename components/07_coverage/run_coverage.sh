#!/bin/bash
# components/07_coverage/run_coverage.sh
# Step 7: Panel coverage plot and statistics
#
# Expects (set by orchestrator):
#   BAM_FILE_CNV, CNV_DIR, R1_base
#   PANEL_REGIONS, PROJECT_DIR
#   (Analysis env + venv already activated by orchestrator)

require_vars BAM_FILE_CNV CNV_DIR R1_base PANEL_REGIONS PROJECT_DIR

_STEP_T0=$(date +%s)
step_start "07 · Coverage — panel depth plot"

_COVERAGE_SCRIPT="$PROJECT_DIR/components/07_coverage/coverage_plot.py"
COVERAGE_DIR="$CNV_DIR/coverage"

if run_if_missing "$COVERAGE_DIR/${R1_base}_panel_coverage.png" "panel coverage plot"; then
    mkdir -p "$COVERAGE_DIR"
    echo "   Generating panel coverage for $(basename "$BAM_FILE_CNV")..."
    python "$_COVERAGE_SCRIPT" \
        "$PANEL_REGIONS" \
        "$BAM_FILE_CNV" \
        "$COVERAGE_DIR/${R1_base}_panel_coverage.png" \
        "$COVERAGE_DIR/${R1_base}_panel_coverage.txt"
fi

step_end "07 · Coverage" "$_STEP_T0"
