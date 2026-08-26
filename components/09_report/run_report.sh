#!/bin/bash
# components/09_report/run_report.sh
# Step 9: Arriba TSV → Excel conversion + final PDF report generation
#
# Expects (set by orchestrator):
#   ARRIBA_OUT, OUT_DIR, R1_base, PROJECT_DIR
#   VAR_ARG  - either "" or "--variants-json <path>" (set by step 08)
#   (Analysis env + venv already activated by orchestrator)

require_vars ARRIBA_OUT OUT_DIR R1_base PROJECT_DIR

_STEP_T0=$(date +%s)
step_start "09 · Report — Arriba Excel + PDF report"

_TSV_TO_EXCEL_SCRIPT="$PROJECT_DIR/components/09_report/tsv_to_excel.py"
_REPORT_SCRIPT="$PROJECT_DIR/components/09_report/ngs_report.py"

# --- Convert Arriba fusions TSV to Excel ---
ARRIBA_XLSX="${ARRIBA_OUT%.tsv}.xlsx"
if [ -f "$ARRIBA_OUT" ]; then
    if run_if_missing "$ARRIBA_XLSX" "Arriba TSV → Excel conversion"; then
        echo "   Converting Arriba fusions to Excel..."
        python "$_TSV_TO_EXCEL_SCRIPT" "$ARRIBA_OUT" "$ARRIBA_XLSX"
    fi
fi

# --- Generate final PDF report ---
# Always regenerate if VAR_ARG is set (variants changed) or report is missing
_REPORT_PDF="$OUT_DIR/${R1_base}_ngs_report.pdf"
if [ ! -f "$_REPORT_PDF" ] || [ -n "${VAR_ARG:-}" ]; then
    echo "   Generating final PDF report..."
    python "$_REPORT_SCRIPT" \
        "$OUT_DIR" \
        "${R1_base}" \
        ${VAR_ARG:-}
fi

step_end "09 · Report" "$_STEP_T0"
