#!/bin/bash
# ngs_tumor_pipeline.sh - Unified NGS Tumor Pipeline
# Usage: bash ngs_tumor_pipeline.sh <R1.fastq.gz> <R2.fastq.gz>


# Source configuration
if [ -z "$PROJECT_DIR" ]; then
    # Determine project root from script location if not inherited (e.g., manual local run)
    load_modules "$ANALYSIS_TOOLCHAIN_MODULE" "${ARRIBA_VISUALIZATION_MODULES[@]}"
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
trap 'echo "? Pipeline failed at line $LINENO: $BASH_COMMAND" >&2' ERR

# Input Validation
if [ "$#" -lt 2 ]; then
    echo "Error: Two input fastq.gz files are required."
    echo "Usage: bash $0 <R1.fastq.gz> <R2.fastq.gz>"
    exit 1
fi

R1_PATH="$1"
R2_PATH="$2"

# --- Step 1: Bioinformatics (fastp, STAR, SAMtools, BWA-MEM2, Arriba) ---
purge_modules
load_modules "$FASTP_TOOLCHAIN_MODULE" "${FASTP_MODULES[@]}"

# Resource Settings
THREADS=${SLURM_CPUS_PER_TASK:-$PIPELINE_THREADS}

# --- Path Setup ---
R1_base=$(basename "$R1_PATH" .fastq.gz)
R2_base=$(basename "$R2_PATH" .fastq.gz)
CASE_LABEL="${R1_base%_R1_001}"

OUT_DIR="$RESULTS_BASE/${CASE_LABEL}"
TMP_DIR="$SCRATCH_DIR/tmp/${CASE_LABEL}"
CNV_DIR="$OUT_DIR/cnv"
KRAKEN_DIR="$OUT_DIR/kraken2"
NONHUMAN_DIR="$OUT_DIR/nonhuman"
LOG_DIR="$OUT_DIR/log"

BAM_FILE_ARRIBA="$TMP_DIR/${R1_base}_Aligned.sortedByCoord.out.arriba.bam"
BAM_FILE_CNV="$TMP_DIR/${R1_base}_Aligned.sortedByCoord.out.cnv.bam"

ARRIBA_OUT="$OUT_DIR/arriba/${R1_base}_fusions.tsv"
FASTP_DIR="$OUT_DIR/fastp"
R1_TRIMMED="$TMP_DIR/${R1_base}.trimmed.fq.gz"
R2_TRIMMED="$TMP_DIR/${R2_base}.trimmed.fq.gz"

# Dynamic CNV file definitions based directly on the CNV BAM file name
CNV_BASE=$(basename "$BAM_FILE_CNV" .bam)
CNR_FILE="$CNV_DIR/${CNV_BASE}.cnr"
CNS_FILE="$CNV_DIR/${CNV_BASE}.cns"

# Create required directories
mkdir -p "$TMP_DIR" "$CNV_DIR" "$OUT_DIR/arriba" "$OUT_DIR/fastp" "$LOG_DIR"



# Defaults
TIMELOG=false

# --- 1. Argument Parsing ---
while [[ $# -gt 2 ]]; do
    case "$3" in
        --timelog)
            TIMELOG=true
            echo -e "Timelog enabled. The Runtimes for each step will be recorded and exported into the logfolder"
            echo -e "Step \tCase \tsize_in_GB \tPOSIX \tseconds" > "$LOG_DIR/${R1_base}_runtimes.txt"

            R1_size=$(wc -c < "$R1_PATH")
            R2_size=$(wc -c < "$R2_PATH")
            combined_bytes=$(( R1_size + R2_size ))
            combined_size_gb=$(printf "%.2f" "$(echo "scale=2; $combined_bytes / 1073741824" | bc)")
            echo -e "Preprocessing \t$CASE_LABEL \t$combined_size_gb \t00:00:00 \t0" >> "$LOG_DIR/${R1_base}_runtimes.txt"

            shift
            ;;
    esac
done



#logging function for when logging time has been requested by the user. else return 0
timelog_step() {
    local label=$1

    

    [[ "$TIMELOG" = true ]] || return 0

    if [[ -z ${STEPTIME:-} ]]; then
        STEPTIME=$(date +%s)
        return 0
    fi

    local END_TIME DURATION
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - STEPTIME))

    printf '%s\t%s\t%s\t%02d:%02d:%02d\t%s\n' \
        "$label" \
        "$CASE_LABEL" \
        "$combined_size_gb" \
        $((DURATION/3600)) \
        $((DURATION%3600/60)) \
        $((DURATION%60)) \
        "$DURATION" >> "$LOG_DIR/${R1_base}_runtimes.txt"
    echo "measured $label"
    unset STEPTIME
    return 0
}

timelog_step "fastp"
#measured code

echo "Starting ngs_tumor_pipeline for $CASE_LABEL on $(hostname)"
echo "Using $THREADS threads"
echo "fastp Preprocessing"


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

timelog_step "fastp"

timelog_step "STAR_for_Arriba"

### STAR Alignment for Arriba ################################################
if [ ! -f "$BAM_FILE_ARRIBA" ]; then
    echo "Running STAR alignment for Arriba (index: $STAR_INDEX)..."
    rm -f "$TMP_DIR/star_tmp_arriba"*
    purge_modules
    load_modules "$STAR_TOOLCHAIN_MODULE" "${STAR_MODULES[@]}" "${SAMTOOLS_MODULES[@]}"
    STAR \
        --runThreadN "$THREADS" \
        --outFileNamePrefix "$TMP_DIR/arriba_" \
        --genomeDir "$STAR_INDEX" --genomeLoad NoSharedMemory \
        --readFilesIn "$R1_TRIMMED" "$R2_TRIMMED" --readFilesCommand zcat \
        --outStd BAM_Unsorted --outSAMtype BAM Unsorted --outSAMunmapped Within --outBAMcompression 0 \
        --outFilterMultimapNmax 50 --peOverlapNbasesMin 10 --alignSplicedMateMapLminOverLmate 0.5 --alignSJstitchMismatchNmax 5 -1 5 5 \
        --chimSegmentMin 10 --chimOutType WithinBAM HardClip --chimJunctionOverhangMin 10 --chimScoreDropMax 30 --chimScoreJunctionNonGTAG 0 --chimScoreSeparation 1 --chimSegmentReadGapMax 3 --chimMultimapNmax 50 | \
    samtools sort -@ "$THREADS" -m $((SORT_MEM_BASE/THREADS))M -T "$TMP_DIR/star_tmp_arriba" -O bam -o "$BAM_FILE_ARRIBA"
    samtools index "$BAM_FILE_ARRIBA"
fi
timelog_step "STAR_for_Arriba"

timelog_step "BWA_MEM2"

echo "BWA-MEM2 Alignment for CNV"
### BWA-MEM2 Alignment for CNV #############################################
if [ ! -f "$BAM_FILE_CNV" ]; then
    echo "Running BWA-MEM2 alignment for CNV (reference: $REF_GENOME_CNV)..."

    # Load dedicated BWA environment from config (swaps to 2024a/GCC13)
    purge_modules
    load_modules "$BWA_TOOLCHAIN_MODULE" "${BWA_MODULES[@]}" "${SAMTOOLS_MODULES[@]}"

    if ! command -v "$BWA_BIN" >/dev/null 2>&1; then
        echo "Error: BWA/BWA-MEM2 binary not found (BWA_BIN=$BWA_BIN)." >&2
        exit 1
    fi
    if [ ! -f "$REF_GENOME_CNV" ]; then
        echo "Error: CNV reference file not found at $REF_GENOME_CNV." >&2
        exit 1
    fi

    "$BWA_BIN" mem -t "$THREADS" "$REF_GENOME_CNV" "$R1_TRIMMED" "$R2_TRIMMED" | \
    samtools sort -@ "$THREADS" -m $((SORT_MEM_BASE/THREADS))M -T "$TMP_DIR/bwa_tmp_cnv" -O bam -o "$BAM_FILE_CNV"
    samtools index "$BAM_FILE_CNV"
fi

timelog_step "BWA_MEM2"
timelog_step "Arriba"
### Arriba Fusion Detection ############################################
if [ ! -f "$ARRIBA_OUT" ]; then
    echo "Running Arriba fusion detection..."
    ARRIBA_BIN="arriba"
    if [ -f "$ARRIBA_BASE/arriba" ]; then
        ARRIBA_BIN="$ARRIBA_BASE/arriba"
    fi

    REF_GENOME_FOR_ARRIBA="${REF_GENOME_ARRIBA:-$REF_GENOME}"
    ANNOTATION_GTF_FOR_ARRIBA="${ANNOTATION_GTF_ARRIBA:-$ANNOTATION_GTF}"

    "$ARRIBA_BIN" \
        -x "$BAM_FILE_ARRIBA" \
        -o "$ARRIBA_OUT" \
        -f intronic,in_vitro,internal_tandem_duplication \
        -a "$REF_GENOME_FOR_ARRIBA" -g "$ANNOTATION_GTF_FOR_ARRIBA" -b "$ARRIBA_BLACKLIST" -k "$ARRIBA_KNOWN_FUSIONS" -t "$ARRIBA_TAGS" -p "$ARRIBA_PROTEIN_DOMAINS"

    # Visualization
    purge_modules
    load_modules "$ANALYSIS_TOOLCHAIN_MODULE" "${ARRIBA_VISUALIZATION_MODULES[@]}"

    DRAW_FUSIONS_R="draw_fusions.R"
    if [ -f "$ARRIBA_BASE/draw_fusions.R" ]; then
        DRAW_FUSIONS_R="$ARRIBA_BASE/draw_fusions.R"
    elif [ -f "$BASE_DIR/bin/draw_fusions.R" ]; then
        DRAW_FUSIONS_R="$BASE_DIR/bin/draw_fusions.R"
    fi

    "$DRAW_FUSIONS_R" \
        --fusions="$ARRIBA_OUT" \
        --alignments="$BAM_FILE_ARRIBA" \
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
        "$QUANTIFY_VIRUS_SH" "$BAM_FILE_ARRIBA" "$OUT_DIR/arriba/${R1_base}_virus_expression.tsv" || true
    fi
fi

# --- Step 2: Downstream Analysis (CNVkit, Custom Visualizations, Reporting) ---
purge_modules
load_modules "$ANALYSIS_TOOLCHAIN_MODULE" "${PYTHON_MODULES[@]}"
load_modules "$ANALYSIS_TOOLCHAIN_MODULE" "${R_BIOCONDUCTOR_MODULES[@]}"

load_ngs_python_env
unset PYTHONPATH

echo "finishing arriba"

# Convert Arriba fusions TSV to Excel
ARRIBA_XLSX="${ARRIBA_OUT%.tsv}.xlsx"
if [ -f "$ARRIBA_OUT" ]; then
    echo "Converting Arriba fusions TSV to Excel..."
    python "$PROJECT_DIR/scripts/tsv_to_excel.py" "$ARRIBA_OUT" "$ARRIBA_XLSX"
fi

timelog_step "Arriba"

echo "CNV-Calling"
timelog_step "CNVKit"
### CNV calling with CNVkit #################################################
if [ ! -f "$CNS_FILE" ]; then
    echo "Running CNVkit batch..."
    # Using --processes 0 to prevent cluster semaphore allocation errors
    cnvkit.py batch "$BAM_FILE_CNV" --reference "$CNV_REFERENCE" --processes 0 \
        --drop-low-coverage --output-dir "$CNV_DIR" --diagram
fi

timelog_step "CNVKit"
timelog_step "CNVKitSex"

echo "CNV Sex Call"
# CNVkit sex call
if [ ! -f "$CNV_DIR/${R1_base}_sex.txt" ]; then
    echo "Running CNVkit sex call..."
    target_cnns=("$CNV_DIR"/*.targetcoverage.cnn)
    antitarget_cnns=("$CNV_DIR"/*.antitargetcoverage.cnn)
    if [ -f "${target_cnns[0]}" ] && [ -f "${antitarget_cnns[0]}" ]; then
        cnvkit.py sex "$CNV_REFERENCE" "${target_cnns[0]}" "${antitarget_cnns[0]}" -o "$CNV_DIR/${R1_base}_sex.txt"
    fi
fi

timelog_step "CNVKitSex"
timelog_step "CNVKitScatter"

echo "CNV Scatter Plots"
### CNV Scatter Plots #######################################################
if [ ! -f "$CNV_DIR/${R1_base}_chrY.png" ]; then
    if [ ! -s "$CNR_FILE" ] || [ ! -s "$CNS_FILE" ]; then
        echo "??  Missing CNVkit outputs ($CNR_FILE or $CNS_FILE). Skipping CNV scatter plots."
    else
        echo "Generating chromosome-wise CNV scatter plots..."
        CNR_GENES=$(cut -f4 "$CNR_FILE" 2>/dev/null | sort -u)
        if [ -z "$CNR_GENES" ]; then
            echo "??  No gene entries found in $CNR_FILE. Skipping CNV scatter plots."
            CNR_GENES=""
        fi

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
fi
timelog_step "CNVKitScatter"

timelog_step "PlotPurity_PanelCoverage"
### Custom Plots & Reporting ################################# Rhine-Westphalia ---

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
        "$BAM_FILE_CNV" \
        "$COVERAGE_DIR/${R1_base}_panel_coverage.png" \
        "$COVERAGE_DIR/${R1_base}_panel_coverage.txt"
fi
timelog_step "PlotPurity_PanelCoverage"
timelog_step "Metagenomics_Kraken2"
mean_coverage=$(awk -F'\t' '{sum += $3; n++} END {print sum / n}' "$COVERAGE_DIR/${R1_base}_panel_coverage.txt")
#echo "${mean_coverage}"

if awk -v m="$mean_coverage" 'BEGIN { exit !(m > 100) }'; then
  echo "mean coverage is greater than 100"
  #metagenomics=FALSE
  echo "Fall ist kein Metagenomics, Kraken2 wird geskippt"
  timelog_step "no_Metagenomics"
else
  echo "mean coverage is 100 or less"
  #metagenomics=TRUE
  echo "Fall ist Metagenomics, Kraken2 wird gestartet"



  mkdir -p "$KRAKEN_DIR"
  mkdir -p "$NONHUMAN_DIR"
  purge_modules
  load_modules "$ANALYSIS_TOOLCHAIN_MODULE" "${KRAKEN2_MODULES[@]}"


  echo "starting bowtie alignment"
  bowtie2 -x $BOWTIE_INDEX -p $PIPELINE_THREADS -1 "$R1_TRIMMED" \
    -2 "$R2_TRIMMED" \
        --un-conc-gz "$TMP_DIR"/${R1_base}_nonhuman_reads \
        -S "$TMP_DIR"/${R1_base}_host_alignment.sam

  mv "$TMP_DIR"/${R1_base}_nonhuman_reads.1 "$NONHUMAN_DIR"/${R1_base}_nonhuman_reads.fastq.gz
  mv "$TMP_DIR"/${R1_base}_nonhuman_reads.2 "$NONHUMAN_DIR"/${R2_base}_nonhuman_reads.fastq.gz



#  kraken2 --paired --threads $PIPELINE_THREADS --memory-mapping --db $PPFDB --classified-out "$TMP_DIR/${R1_base}_classified_ppf#.fastq" \
#  --unclassified-out "$TMP_DIR/${R1_base}_not_classified_ppf#.fastq" --report "$KRAKEN_DIR/${R1_base}_kraken2_ppf_report.txt" \
#  --output "$TMP_DIR/${R1_base}_kraken2_ppf_output.txt" --report-minimizer-data "$NONHUMAN_DIR"/${R1_base}_nonhuman_reads.fastq.gz "$NONHUMAN_DIR"/${R2_base}_nonhuman_reads.fastq.gz


  kraken2 --paired --threads $PIPELINE_THREADS --memory-mapping --db $EUPATHDB --classified-out "$TMP_DIR/${R1_base}_classified_eupathdb#.fastq" \
  --unclassified-out "$TMP_DIR/${R1_base}_not_classified_eupathdb#.fastq" --report "$KRAKEN_DIR/${R1_base}_kraken2_eupathdb_report.txt" \
  --output "$TMP_DIR/${R1_base}_kraken2_eupathdb_output.txt" --report-minimizer-data "$NONHUMAN_DIR"/${R1_base}_nonhuman_reads.fastq.gz "$NONHUMAN_DIR"/${R2_base}_nonhuman_reads.fastq.gz 

#   krakenuniq \
#     --report-file "$OUT_DIR"/kraken/${R1_base}.krakenuniq.report.txt \
#     --db $DATABASE \
#     --threads $THREADS \
#     --output - \
#     --paired "$OUT_DIR"/nonhuman_reads/${R1_base}_nonhuman_reads.fastq.gz "$OUT_DIR"/nonhuman_reads/${R2_base}_nonhuman_reads.fastq.gz
timelog_step "Metagenomics_Kraken2"
fi

timelog_step "VariantProcessing"
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
        --ref-dir "$PROJECT_DIR/resources" \
        -o "$PROCESSED_VARS"
    VAR_ARG="--variants-json $PROCESSED_VARS"
fi

timelog_step "VariantProcessing"
timelog_step "Report"

### Final PDF Report
if [ ! -f "$OUT_DIR/${R1_base}_ngs_report.pdf" ] || [ -n "$VAR_ARG" ]; then
    echo "Generating Final PDF Report..."
    python "$PROJECT_DIR/scripts/ngs_report.py" "$OUT_DIR" "${R1_base}" $VAR_ARG
fi
timelog_step "Report"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
echo "-------------------------------------------------------"
echo "? Pipeline finished for ${CASE_LABEL}"
echo "?? Elapsed time: $(printf '%02d:%02d:%02d' $((DURATION/3600)) $((DURATION%3600/60)) $((DURATION%60))) $DURATION"
echo "-------------------------------------------------------"
