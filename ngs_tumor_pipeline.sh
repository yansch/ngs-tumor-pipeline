#!/bin/bash
# ngs_tumor_pipeline.sh - NGS Tumor Pipeline Orchestrator
# Usage: bash ngs_tumor_pipeline.sh <R1.fastq.gz> <R2.fastq.gz>
#
# This script is the thin orchestrator. All processing logic lives in
# the individual component scripts under components/*/run_*.sh.

# ---------------------------------------------------------------------------
# 0. Bootstrap: locate project root and load config
# ---------------------------------------------------------------------------
export PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

source "$PROJECT_DIR/config/common.sh"
source "$PROJECT_DIR/lib/common_functions.sh"

START_TIME=$(date +%s)
set -eo pipefail
trap 'echo "❌ Pipeline failed at line $LINENO: $BASH_COMMAND" >&2' ERR

# ---------------------------------------------------------------------------
# 1. Input validation
# ---------------------------------------------------------------------------
if [ "$#" -lt 2 ]; then
    echo "Error: Two input fastq.gz files are required."
    echo "Usage: bash $0 <R1.fastq.gz> <R2.fastq.gz>"
    exit 1
fi

R1_PATH="$1"
R2_PATH="$2"

# ---------------------------------------------------------------------------
# 2. Path & directory setup (shared across all component steps)
# ---------------------------------------------------------------------------
THREADS=${SLURM_CPUS_PER_TASK:-$PIPELINE_THREADS}

R1_base=$(basename "$R1_PATH" .fastq.gz)
R2_base=$(basename "$R2_PATH" .fastq.gz)
export CASE_LABEL="${R1_base%_R1_001}"

export OUT_DIR="$RESULTS_BASE/${CASE_LABEL}"
export TMP_DIR="$SCRATCH_DIR/tmp/${CASE_LABEL}"
export CNV_DIR="$OUT_DIR/cnv"
export LOG_DIR="$OUT_DIR/log"

export BAM_FILE_ARRIBA="$TMP_DIR/${R1_base}_Aligned.sortedByCoord.out.arriba.bam"
export BAM_FILE_CNV="$TMP_DIR/${R1_base}_Aligned.sortedByCoord.out.cnv.bam"

export ARRIBA_OUT="$OUT_DIR/arriba/${R1_base}_fusions.tsv"
export FASTP_DIR="$OUT_DIR/fastp"
export R1_TRIMMED="$TMP_DIR/${R1_base}.trimmed.fq.gz"
export R2_TRIMMED="$TMP_DIR/${R2_base}.trimmed.fq.gz"
export FASTP_JSON="$FASTP_DIR/${R1_base}.fastp.json"

# CNV file paths derived from the CNV BAM name
CNV_BASE=$(basename "$BAM_FILE_CNV" .bam)
export CNR_FILE="$CNV_DIR/${CNV_BASE}.cnr"
export CNS_FILE="$CNV_DIR/${CNV_BASE}.cns"

mkdir -p "$TMP_DIR" "$CNV_DIR" "$OUT_DIR/arriba" "$OUT_DIR/fastp" "$LOG_DIR"

echo "═══════════════════════════════════════════════════════════════════════"
echo "🧬 NGS Tumor Pipeline  |  Case: $CASE_LABEL"
echo "   Host: $(hostname)   Threads: $THREADS"
echo "═══════════════════════════════════════════════════════════════════════"

# ---------------------------------------------------------------------------
# 3. Bioinformatics steps (FASTQ → BAMs)
#    Each step handles its own module loading.
# ---------------------------------------------------------------------------
source "$PROJECT_DIR/components/01_fastp/run_fastp.sh"
source "$PROJECT_DIR/components/02_star/run_star.sh"
source "$PROJECT_DIR/components/03_bwa_mem/run_bwa_mem.sh"
source "$PROJECT_DIR/components/04_arriba/run_arriba.sh"

# ---------------------------------------------------------------------------
# 4. Switch to analysis environment (Python + R)
#    This is a deliberate environment boundary between alignment and analysis.
# ---------------------------------------------------------------------------
purge_modules
load_modules "$ANALYSIS_TOOLCHAIN_MODULE" "${PYTHON_MODULES[@]}"
load_modules "$ANALYSIS_TOOLCHAIN_MODULE" "${R_BIOCONDUCTOR_MODULES[@]}"
load_ngs_python_env
unset PYTHONPATH

echo ""
echo "─── Analysis environment ready ─────────────────────────────────────────"

# ---------------------------------------------------------------------------
# 5. Analysis steps (BAMs → results)
# ---------------------------------------------------------------------------
source "$PROJECT_DIR/components/05_cnvkit/run_cnvkit.sh"
source "$PROJECT_DIR/components/06_cnv_plots/run_cnv_plots.sh"
source "$PROJECT_DIR/components/07_coverage/run_coverage.sh"
source "$PROJECT_DIR/components/08_variants/run_variants.sh"
source "$PROJECT_DIR/components/09_report/run_report.sh"

# ---------------------------------------------------------------------------
# 6. Summary
# ---------------------------------------------------------------------------
END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))
echo ""
echo "═══════════════════════════════════════════════════════════════════════"
echo "✅ Pipeline finished for ${CASE_LABEL}"
echo "⏱️  Elapsed: $(printf '%02d:%02d:%02d' $(( DURATION/3600 )) $(( DURATION%3600/60 )) $(( DURATION%60 )))"
echo "📂 Results: $OUT_DIR"
echo "═══════════════════════════════════════════════════════════════════════"