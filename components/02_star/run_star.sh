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

    #uncompressing before, instead of star uncompressing whilst executing itself, fixes local execution failing due to eof.
    UNCOMP_DIR="$TMP_DIR/star_fastq_uncompressed"
    mkdir -p "$UNCOMP_DIR"
    
    echo "Uncompressing fastqs"
    
    zcat "$R1_TRIMMED" > "$UNCOMP_DIR/R1.trimmed.fq"
    zcat "$R2_TRIMMED" > "$UNCOMP_DIR/R2.trimmed.fq"
       
    echo "Running STAR"
    STAR \
        --runThreadN "$THREADS" \
        --outFileNamePrefix "$TMP_DIR/arriba_" \
        --genomeDir "$STAR_INDEX" --genomeLoad NoSharedMemory \
        --readFilesIn "$UNCOMP_DIR/R1.trimmed.fq" "$UNCOMP_DIR/R2.trimmed.fq" \
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
    echo "Running samtools index"
    samtools index "$BAM_FILE_ARRIBA"
    
    R1_size=$(wc -c < "$R1_TRIMMED")
    R2_size=$(wc -c < "$R2_TRIMMED")
    BAM_size=$(wc -c < "$BAM_FILE_ARRIBA")
    combined_bytes=$(( R1_size + R2_size ))
    combined_size_mb=$(printf "%.2f" "$(echo "scale=0; $combined_bytes / 1048576" | bc)")
    BAM_size_mb=$(printf "%.2f" "$(echo "scale=0; $BAM_size / 1048576" | bc)")
    
    # Print File Sizes in MB to check for Star Errors in Logs. If huge difference, STAR failed at some point
    echo -e "Trimmed Reads:\t\t$combined_size_mb MB"
    echo -e "BAM File Arriba:\t$BAM_size_mb MB"
    echo "If there is a huge difference in file sizes, this could point to a problem."

    #Cleanup of uncompressed data to save space, especially useful for the local run.
    UNCOMP_SIZE=$(du -sm "$UNCOMP_DIR" | awk '{print $1}')
    rm -rf "$UNCOMP_DIR"
    echo "Cleared $UNCOMP_SIZE MB of uncompressed data."  

fi

step_end "02 · STAR" "$_STEP_T0"
