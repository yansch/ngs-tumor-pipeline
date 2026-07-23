#!/bin/bash
# components/03_bwa_mem/run_bwa_mem.sh
# Step 3: BWA-MEM2 alignment for CNV analysis
#
# Expects (set by orchestrator):
#   R1_TRIMMED, R2_TRIMMED, TMP_DIR, BAM_FILE_CNV
#   THREADS, SORT_MEM_BASE
#   BWA_BIN, REF_GENOME_CNV
#   BWA_TOOLCHAIN_MODULE, BWA_MODULES[@], SAMTOOLS_MODULES[@]
#
# Exports: (BAM_FILE_CNV already set by orchestrator path setup)

require_vars R1_TRIMMED R2_TRIMMED TMP_DIR BAM_FILE_CNV THREADS SORT_MEM_BASE BWA_BIN REF_GENOME_CNV

_STEP_T0=$(date +%s)
step_start "03 · BWA-MEM2 — alignment for CNV"

if run_if_missing "$BAM_FILE_CNV" "BWA-MEM2 alignment"; then
    echo "   Reference: $REF_GENOME_CNV"

    purge_modules
    load_modules "$BWA_TOOLCHAIN_MODULE" "${BWA_MODULES[@]}" "${SAMTOOLS_MODULES[@]}"

    if ! command -v "$BWA_BIN" >/dev/null 2>&1; then
        echo "❌ Error: BWA/BWA-MEM2 binary not found (BWA_BIN=$BWA_BIN)." >&2
        exit 1
    fi
    if [ ! -f "$REF_GENOME_CNV" ]; then
        echo "❌ Error: CNV reference file not found at $REF_GENOME_CNV." >&2
        exit 1
    fi

    "$BWA_BIN" mem -t "$THREADS" "$REF_GENOME_CNV" "$R1_TRIMMED" "$R2_TRIMMED" | \
    samtools sort \
        -@ "$THREADS" \
        -m $(( SORT_MEM_BASE / THREADS ))M \
        -T "$TMP_DIR/bwa_tmp_cnv" \
        -O bam \
        -o "$BAM_FILE_CNV"

    samtools index "$BAM_FILE_CNV"
fi

step_end "03 · BWA-MEM2" "$_STEP_T0"
