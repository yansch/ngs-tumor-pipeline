#!/bin/bash
# components/05_cnvkit/run_cnvkit.sh
# Step 5: CNV calling with CNVkit (batch, sex call, scatter plots)
#
# Expects (set by orchestrator):
#   BAM_FILE_CNV, CNV_DIR, CNV_REFERENCE, R1_base
#   CNR_FILE, CNS_FILE, RELEVANT_GENES
#   (Analysis env + venv already activated by orchestrator)
#
# Exports: (CNR_FILE, CNS_FILE already set by orchestrator path setup)

require_vars BAM_FILE_CNV CNV_DIR CNV_REFERENCE R1_base CNR_FILE CNS_FILE RELEVANT_GENES

_STEP_T0=$(date +%s)
step_start "05 · CNVkit — copy number analysis"

# --- CNVkit batch ---
if run_if_missing "$CNS_FILE" "CNVkit batch"; then
    echo "   Running CNVkit batch on $(basename "$BAM_FILE_CNV")..."
    # --processes 0 prevents cluster semaphore allocation errors
    cnvkit.py batch "$BAM_FILE_CNV" \
        --reference "$CNV_REFERENCE" \
        --processes 0 \
        --drop-low-coverage \
        --output-dir "$CNV_DIR" \
        --diagram
fi

# --- CNVkit sex call ---
if run_if_missing "$CNV_DIR/${R1_base}_sex.txt" "CNVkit sex call"; then
    echo "   Running CNVkit sex call..."
    target_cnns=("$CNV_DIR"/*.targetcoverage.cnn)
    antitarget_cnns=("$CNV_DIR"/*.antitargetcoverage.cnn)
    if [ -f "${target_cnns[0]}" ] && [ -f "${antitarget_cnns[0]}" ]; then
        cnvkit.py sex "$CNV_REFERENCE" \
            "${target_cnns[0]}" \
            "${antitarget_cnns[0]}" \
            -o "$CNV_DIR/${R1_base}_sex.txt"
    else
        echo "   ⚠️  Coverage CNN files not found — skipping sex call."
    fi
fi

# --- CNVkit scatter plots (per chromosome) ---
if run_if_missing "$CNV_DIR/${R1_base}_chrY.png" "CNVkit scatter plots"; then
    if [ ! -s "$CNR_FILE" ] || [ ! -s "$CNS_FILE" ]; then
        echo "   ⚠️  Missing CNVkit outputs ($CNR_FILE or $CNS_FILE). Skipping scatter plots."
    else
        echo "   Generating chromosome-wise CNV scatter plots..."
        CNR_GENES=$(cut -f4 "$CNR_FILE" 2>/dev/null | sort -u)

        for chr in {1..22} X Y; do
            chr_name="chr${chr}"
            potential_genes=$(awk -F';' -v c="$chr_name" '$2 == c {print $1}' "$RELEVANT_GENES")
            gene_list=""
            for g in $potential_genes; do
                if [ -n "$CNR_GENES" ] && echo "$CNR_GENES" | grep -qx "$g"; then
                    gene_list="${gene_list}${g},"
                fi
            done
            gene_list=${gene_list%,}

            gene_args=""
            if [ -n "$gene_list" ]; then
                gene_args="-g $gene_list"
            fi

            cnvkit.py scatter "$CNR_FILE" \
                -s "$CNS_FILE" \
                -c "${chr_name}" \
                --title "${chr_name}" \
                --segment-color 'purple' \
                $gene_args \
                -o "$CNV_DIR/${R1_base}_chr${chr}.png" || :
        done
        echo "   Scatter plots written to $CNV_DIR"
    fi
fi

step_end "05 · CNVkit" "$_STEP_T0"
