#!/bin/bash
# components/06_cnv_plots/run_cnv_plots.sh
# Step 6: Custom genome-wide CNV plots with purity correction
#
# Expects (set by orchestrator):
#   CNR_FILE, CNS_FILE, OUT_DIR, R1_base
#   CYTOBAND_TXT, RELEVANT_GENES, PROJECT_DIR
#   (Analysis env + venv already activated by orchestrator)

require_vars CNR_FILE CNS_FILE OUT_DIR R1_base CYTOBAND_TXT RELEVANT_GENES PROJECT_DIR

_STEP_T0=$(date +%s)
step_start "06 · Custom CNV plots — purity series"

_PLOT_SCRIPT="$PROJECT_DIR/components/06_cnv_plots/plot_cnv_from_ngs.py"

if run_if_missing "$OUT_DIR/cnv/cnv_plot_purity_0.1.png" "custom CNV purity plots"; then
    if [ ! -s "$CNR_FILE" ] || [ ! -s "$CNS_FILE" ]; then
        echo "   ⚠️  Missing CNVkit outputs. Skipping custom CNV plots."
    else
        echo "   Generating CNV plots for purity 1.0 → 0.1..."
        for p_int in {10..1}; do
            purity=$(LC_NUMERIC=C awk -v p="$p_int" 'BEGIN {print p/10}')
            fname=$( [ "$p_int" -eq 10 ] && echo "cnv_plot.png" || echo "cnv_plot_purity_${purity}.png" )
            echo "   Purity ${purity} → ${fname}"
            python "$_PLOT_SCRIPT" \
                "$CNR_FILE" \
                --case-id "${R1_base}" \
                -o "$OUT_DIR/cnv" \
                -f "$fname" \
                --purity "$purity" \
                -c "$CYTOBAND_TXT" \
                -g "$RELEVANT_GENES" || :
        done
    fi
fi

step_end "06 · Custom CNV plots" "$_STEP_T0"
