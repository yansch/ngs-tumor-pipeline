#!/bin/bash
# ngs_tumor_pipeline.sh - Unified NGS Tumor Pipeline
# Usage: bash ngs_tumor_pipeline.sh <R1.fastq.gz> <R2.fastq.gz>

# Source configuration
if [ -z "$PROJECT_DIR" ]; then
    # Determine project root from script location if not inherited (e.g., manual local run)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "$SCRIPT_DIR/config/common.sh" ]]; then
        export PROJECT_DIR="$SCRIPT_DIR"
    elif [[ -f "$SCRIPT_DIR/../config/common.sh" ]]; then
        export PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
    else
        echo "Error: Cannot locate project root (config/common.sh not found)."
        exit 1
    fi
fi
source "$PROJECT_DIR/config/common.sh"

START_TIME=$(date +%s)

# Stop script execution on error
set -eo pipefail
trap 'echo "❌ Pipeline failed at line $LINENO: $BASH_COMMAND" >&2' ERR

# Input Validation
if [ "$#" -lt 2 ]; then
    echo "Error: Two input fastq.gz files are required."
    echo "Usage: bash $0 <R1.fastq.gz> <R2.fastq.gz>"
    exit 1
fi

R1_PATH="$1"
R2_PATH="$2"

# --- Step 1: Bioinformatics (fastp, STAR, SAMtools, Arriba) ---
load_modules "$TOOLCHAIN_BIO" "$FASTP_MODULE" "$STAR_MODULE" "$SAMTOOLS_MODULE"

# Resource Settings
THREADS=${SLURM_CPUS_PER_TASK:-$PIPELINE_THREADS}

# --- Path Setup ---
R1_base=$(basename "$R1_PATH" .fastq.gz)
R2_base=$(basename "$R2_PATH" .fastq.gz)
CASE_LABEL="${R1_base%_R1_001}"

OUT_DIR="$RESULTS_BASE/${CASE_LABEL}"
TMP_DIR="$SCRATCH_DIR/work/${CASE_LABEL}"
CNV_DIR="$OUT_DIR/cnv"
LOG_DIR="$OUT_DIR/log"
BAM_FILE="$TMP_DIR/${R1_base}_Aligned.sortedByCoord.out.bam"
BAM_FILE_CHR="${BAM_FILE%.bam}_chr.bam"
ARRIBA_OUT="$OUT_DIR/arriba/${R1_base}_fusions.tsv"
CNR_FILE="$CNV_DIR/${R1_base}_Aligned.sortedByCoord.out_chr.cnr"
CNS_FILE="$CNV_DIR/${R1_base}_Aligned.sortedByCoord.out_chr.cns"
FASTP_DIR="$OUT_DIR/fastp"
R1_TRIMMED="$TMP_DIR/${R1_base}.trimmed.fq.gz"
R2_TRIMMED="$TMP_DIR/${R2_base}.trimmed.fq.gz"

# Create required directories
mkdir -p "$TMP_DIR" "$CNV_DIR" "$OUT_DIR/arriba" "$OUT_DIR/fastp" "$LOG_DIR"

echo "Starting ngs_tumor_pipeline for $CASE_LABEL on $(hostname)"
echo "Using $THREADS threads"

FASTP_JSON="$FASTP_DIR/${R1_base}.fastp.json"

### fastp Preprocessing #######################################################
if [[ ! -f "$R1_TRIMMED" || ! -f "$FASTP_JSON" ]]; then
    echo "Running fastp preprocessing..."
    fastp \
        -i "$R1_PATH" -I "$R2_PATH" \
        -o "$R1_TRIMMED" -O "$R2_TRIMMED" \
        -p "$THREADS" \
        --low_complexity_filter \
        -h "$FASTP_DIR/${R1_base}.fastp.html" \
        -j "$FASTP_JSON"
fi

# Extract 'total_reads' from fastp.json
if command -v jq &>/dev/null; then
    TOTAL_READS=$(jq -r '.summary.before_filtering.total_reads' "$FASTP_JSON")
else
    TOTAL_READS=$(python3 -c "import json, sys; print(json.load(open(sys.argv[1]))['summary']['before_filtering']['total_reads'])" "$FASTP_JSON")
fi
echo "Total reads: $TOTAL_READS"

### STAR Alignment ##########################################################
if [ ! -f "$BAM_FILE" ]; then
    echo "Running STAR alignment..."
    rm -f "$TMP_DIR/star_tmp"*
    STAR \
        --runThreadN "$THREADS" \
        --outFileNamePrefix "$TMP_DIR/" \
        --genomeDir "$STAR_INDEX" --genomeLoad NoSharedMemory \
        --readFilesIn "$R1_TRIMMED" "$R2_TRIMMED" --readFilesCommand zcat \
        --outStd BAM_Unsorted --outSAMtype BAM Unsorted --outSAMunmapped Within --outBAMcompression 0 \
        --outFilterMultimapNmax 50 --peOverlapNbasesMin 10 --alignSplicedMateMapLminOverLmate 0.5 --alignSJstitchMismatchNmax 5 -1 5 5 \
        --chimSegmentMin 10 --chimOutType WithinBAM HardClip --chimJunctionOverhangMin 10 --chimScoreDropMax 30 --chimScoreJunctionNonGTAG 0 --chimScoreSeparation 1 --chimSegmentReadGapMax 3 --chimMultimapNmax 50 | \
    samtools sort -@ "$THREADS" -m $((SORT_MEM_BASE/THREADS))M -T "$TMP_DIR/star_tmp" -O bam -o "$BAM_FILE"
    samtools index "$BAM_FILE"
fi

### Arriba Fusion Detection ############################################
if [ ! -f "$ARRIBA_OUT" ]; then
    echo "Running Arriba fusion detection..."
    # Check if ARRIBA_BASE points to binary or if we use PATH
    ARRIBA_BIN="arriba"
    if [ -f "$ARRIBA_BASE/arriba" ]; then
        ARRIBA_BIN="$ARRIBA_BASE/arriba"
    fi

    "$ARRIBA_BIN" \
        -x "$BAM_FILE" \
        -o "$ARRIBA_OUT" \
        -f intronic,in_vitro,internal_tandem_duplication \
        -a "$REF_GENOME" -g "$ANNOTATION_GTF" -b "$ARRIBA_BLACKLIST" -k "$ARRIBA_KNOWN_FUSIONS" -t "$ARRIBA_TAGS" -p "$ARRIBA_PROTEIN_DOMAINS"

    # Visualization
    load_modules "$R_MODULE"
    DRAW_FUSIONS_R="draw_fusions.R"
    if [ -f "$ARRIBA_BASE/draw_fusions.R" ]; then
        DRAW_FUSIONS_R="$ARRIBA_BASE/draw_fusions.R"
    elif [ -f "$BASE_DIR/bin/draw_fusions.R" ]; then
        DRAW_FUSIONS_R="$BASE_DIR/bin/draw_fusions.R"
    fi

    "$DRAW_FUSIONS_R" \
        --fusions="$ARRIBA_OUT" \
        --alignments="$BAM_FILE" \
        --output="$OUT_DIR/arriba/${R1_base}_fusions.pdf" \
        --annotation="$ANNOTATION_GTF" \
        --cytobands="$ARRIBA_CYTOBANDS" \
        --proteinDomains="$ARRIBA_PROTEIN_DOMAINS"

    # Virus Expression (Omen feature)
    QUANTIFY_VIRUS_SH="quantify_virus_expression.sh"
    if [ -f "$ARRIBA_BASE/quantify_virus_expression.sh" ]; then
        QUANTIFY_VIRUS_SH="$ARRIBA_BASE/quantify_virus_expression.sh"
    elif [ -f "$BASE_DIR/bin/quantify_virus_expression.sh" ]; then
        QUANTIFY_VIRUS_SH="$BASE_DIR/bin/quantify_virus_expression.sh"
    fi
    
    if command -v "$QUANTIFY_VIRUS_SH" &>/dev/null || [ -f "$QUANTIFY_VIRUS_SH" ]; then
        echo "Quantifying virus expression..."
        "$QUANTIFY_VIRUS_SH" "$BAM_FILE" "$OUT_DIR/arriba/${R1_base}_virus_expression.tsv" || true
    fi
fi

### BAM Re-headering for CNV Compatibility ##################################
if [ ! -f "$BAM_FILE_CHR" ]; then
    echo "Adapting BAM header (adding 'chr' prefix)..."
    samtools view -H "$BAM_FILE" | sed -e '/^@SQ/s/SN:\([^  ]*\)/SN:chr\1/' > "$TMP_DIR/header_chr.sam"
    samtools reheader "$TMP_DIR/header_chr.sam" "$BAM_FILE" > "$BAM_FILE_CHR"
    samtools index "$BAM_FILE_CHR"
fi

if command -v module >/dev/null 2>&1; then
    module --force purge
fi

source "$PROJECT_DIR/config/common.sh"
load_modules "$TOOLCHAIN_PYTHON" "$PYTHON_MODULE"
load_modules "$R_PYTHON_COMPAT_MODULE" # This now pulls in palma/2024a safely

load_ngs_python_env

unset PYTHONPATH
export MPLBACKEND=Agg

echo "Starting analysis for $CASE_LABEL..."

### CNV calling with CNVkit ################################################################
if [ ! -f "$CNS_FILE" ]; then
    echo "Running CNVkit batch..."
    # cnvkit.py will now use the Python from your venv but can find
    # the R 4.4.2 libraries it needs for plotting/calculations.
    cnvkit.py batch "$BAM_FILE_CHR" --reference "$CNV_REFERENCE" --processes "$THREADS" \
        --drop-low-coverage --output-dir "$CNV_DIR" --diagram
fi

# CNVkit sex call (Omen feature)
if [ ! -f "$CNV_DIR/${R1_base}_sex.txt" ]; then
    echo "Running CNVkit sex call..."
    target_cnns=("$CNV_DIR"/*.targetcoverage.cnn)
    antitarget_cnns=("$CNV_DIR"/*.antitargetcoverage.cnn)
    if [ -f "${target_cnns[0]}" ] && [ -f "${antitarget_cnns[0]}" ]; then
        cnvkit.py sex "$CNV_REFERENCE" "${target_cnns[0]}" "${antitarget_cnns[0]}" -o "$CNV_DIR/${R1_base}_sex.txt"
    fi
fi

### CNV Scatter Plots (Omen feature) #######################################################
if [ ! -f "$CNV_DIR/${R1_base}_chrY.png" ]; then
    echo "Generating chromosome-wise CNV scatter plots..."
    CNR_GENES=$(cut -f4 "$CNR_FILE" | sort -u)

    for chr in {1..22} X Y; do
        chr_name="chr${chr}"
        potential_genes=$(awk -F';' -v c="$chr_name" '$2 == c {print $1}' "$RELEVANT_GENES")
        gene_list=""
        for g in $potential_genes; do
            if echo "$CNR_GENES" | grep -qx "$g"; then
                gene_list="${gene_list}${g},"
            fi
        done
        gene_list=${gene_list%,}

        gene_args=""
        if [ ! -z "$gene_list" ]; then
            gene_args="-g $gene_list"
        fi

        echo "Plotting CNV scatter for ${chr_name}..."
        cnvkit.py scatter "$CNR_FILE" \
            -s "$CNS_FILE" \
            -c "${chr_name}" \
            --title "${chr_name}" \
            --segment-color 'purple' \
            $gene_args \
            -o "$CNV_DIR/${R1_base}_chr${chr}.png" || :
    done
fi

### Custom Plots & Reporting #################################################

# Purity Plots
if [ ! -f "$OUT_DIR/cnv/cnv_plot_purity_0.1.png" ]; then
    for p_int in {10..1}; do
        purity=$(LC_NUMERIC=C awk -v p="$p_int" 'BEGIN {print p/10}')
        fname=$( [ "$p_int" -eq 10 ] && echo "cnv_plot.png" || echo "cnv_plot_purity_${purity}.png" )
        echo "Generating CNV plot for purity ${purity}..."
        python "$PROJECT_DIR/scripts/plot_cnv_from_ngs.py" "$CNR_FILE" --case-id "${R1_base}" -o "$OUT_DIR/cnv" -f "$fname" --purity "$purity" -c "$CYTOBAND_TXT" -g "$RELEVANT_GENES" || :
    done
fi

# Panel Coverage
COVERAGE_DIR="$CNV_DIR/coverage"
if [ ! -f "$COVERAGE_DIR/${R1_base}_panel_coverage.png" ]; then
    mkdir -p "$COVERAGE_DIR"
    echo "Generating Panel Coverage..."
    python "$PROJECT_DIR/scripts/coverage_plot.py" \
        "$PANEL_REGIONS" \
        "$BAM_FILE_CHR" \
        "$COVERAGE_DIR/${R1_base}_panel_coverage.png" \
        "$COVERAGE_DIR/${R1_base}_panel_coverage.txt"
fi

### Variant Processing (Omen feature) ####################################################
VARIANTS_JSON="${VARIANTS_SEARCH_DIR}/${CASE_LABEL}.json.gz"
if [ ! -f "$VARIANTS_JSON" ]; then
    VARIANTS_JSON="${VARIANTS_SEARCH_DIR}/${CASE_LABEL}.json"
fi

# Fallback search
if [ ! -f "$VARIANTS_JSON" ]; then
    echo "Searching for matching variant file in $VARIANTS_SEARCH_DIR..."
    for f in "$VARIANTS_SEARCH_DIR"/*.hard-filtered.vcf.annotated.json*; do
        [ -e "$f" ] || continue
        fname=$(basename "$f")
        prefix="${fname%%.hard-filtered*}"
        if [[ "$CASE_LABEL" == *"$prefix"* ]]; then
            echo "Found match by prefix: $prefix -> $fname"
            VARIANTS_JSON="$f"
            break
        fi
    done
fi

VARIANTS_DIR="$OUT_DIR/variants"
mkdir -p "$VARIANTS_DIR"
PROCESSED_VARS="$VARIANTS_DIR/${CASE_LABEL}_variants_processed.json"
VAR_ARG=""

if [ -f "$VARIANTS_JSON" ]; then
    echo "Processing variants: $VARIANTS_JSON"
    python "$PROJECT_DIR/scripts/ngs_variant_processor.py" "$VARIANTS_JSON" \
        --ref-dir "$REF_BASE" \
        -o "$PROCESSED_VARS"
    VAR_ARG="--variants-json $PROCESSED_VARS"
fi

### Final PDF Report
if [ ! -f "$OUT_DIR/${R1_base}_ngs_report.pdf" ] || [ ! -z "$VAR_ARG" ]; then
    echo "Generating Final PDF Report..."
    python "$PROJECT_DIR/scripts/ngs_report.py" "$OUT_DIR" "${R1_base}" $VAR_ARG
fi

# --- Cleanup ---
echo "Cleaning up temporary files in $TMP_DIR..."
# rm -rf "$TMP_DIR" # Uncomment after verification

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
echo "--------------------------------------------------------------------------------"
echo "✅ Pipeline finished for ${CASE_LABEL}"
echo "⏱️ Elapsed time: $(printf '%02d:%02d:%02d' $((DURATION/3600)) $((DURATION%3600/60)) $((DURATION%60)))"
echo "--------------------------------------------------------------------------------"
