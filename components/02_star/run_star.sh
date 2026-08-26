#!/bin/bash
# components/02_star/run_star.sh
# Step 2: STAR alignment for Arriba fusion detection
#
# Expects (set by orchestrator):
#   R1_TRIMMED, R2_TRIMMED, TMP_DIR, BAM_FILE_ARRIBA
#   THREADS, SORT_MEM_BASE
#   STAR_INDEX, STAR_TOOLCHAIN_MODULE, STAR_MODULES[@], SAMTOOLS_MODULES[@]
#
# Exports: (BAM_FILE_ARRIBA already set by orchestrator path setup)

require_vars R1_TRIMMED R2_TRIMMED TMP_DIR BAM_FILE_ARRIBA THREADS SORT_MEM_BASE STAR_INDEX

_STEP_T0=$(date +%s)
step_start "02 · STAR — alignment for Arriba"

if run_if_missing "$BAM_FILE_ARRIBA" "STAR alignment"; then
    echo "   STAR index: $STAR_INDEX"
    rm -f "$TMP_DIR/star_tmp_arriba"*

    purge_modules
    load_modules "$STAR_TOOLCHAIN_MODULE" "${STAR_MODULES[@]}" "${SAMTOOLS_MODULES[@]}"

    STAR \
        --runThreadN "$THREADS" \
        --outFileNamePrefix "$TMP_DIR/arriba_" \
        --genomeDir "$STAR_INDEX" --genomeLoad NoSharedMemory \
        --readFilesIn "$R1_TRIMMED" "$R2_TRIMMED" --readFilesCommand zcat \
        --outStd BAM_Unsorted --outSAMtype BAM Unsorted \
        --outSAMunmapped Within --outBAMcompression 0 \
        --outFilterMultimapNmax 50 --peOverlapNbasesMin 10 \
        --alignSplicedMateMapLminOverLmate 0.5 \
        --alignSJstitchMismatchNmax 5 -1 5 5 \
        --chimSegmentMin 10 --chimOutType WithinBAM HardClip \
        --chimJunctionOverhangMin 10 --chimScoreDropMax 30 \
        --chimScoreJunctionNonGTAG 0 --chimScoreSeparation 1 \
        --chimSegmentReadGapMax 3 --chimMultimapNmax 50 | \
    samtools sort \
        -@ "$THREADS" \
        -m $(( SORT_MEM_BASE / THREADS ))M \
        -T "$TMP_DIR/star_tmp_arriba" \
        -O bam \
        -o "$BAM_FILE_ARRIBA"

    samtools index "$BAM_FILE_ARRIBA"
fi

step_end "02 · STAR" "$_STEP_T0"
