#!/bin/bash
# config/palma.sh - Palma-specific configuration

export HAS_MODULE_SYSTEM=true

# --- Ordered module groups ---
# Preprocessing (fastp)
export FASTP_TOOLCHAIN_MODULE="palma/2022a"
FASTP_MODULES=("GCC/11.3.0" "fastp/0.23.2")

# Alignment (STAR)
export STAR_TOOLCHAIN_MODULE="palma/2024a"
STAR_MODULES=("GCC/13.3.0" "STAR/2.7.11b")

# SAMtools (for STAR/BWA pipes)
export SAMTOOLS_TOOLCHAIN_MODULE="palma/2024a"
SAMTOOLS_MODULES=("GCC/13.3.0" "SAMtools/1.21")

export BWA_TOOLCHAIN_MODULE="palma/2024a"
BWA_MODULES=("GCC/13.3.0" "bwa-mem2/2.2.1")

# Downstream Analysis Group
export ANALYSIS_TOOLCHAIN_MODULE="palma/2024a"
PYTHON_MODULES=("GCCcore/13.3.0" "Python/3.12.3")
ARRIBA_VISUALIZATION_MODULES=("GCC/13.3.0" "OpenMPI/5.0.3" "R-bundle-Bioconductor/3.20-R-4.4.2")
R_BIOCONDUCTOR_MODULES=("GCC/13.3.0" "OpenMPI/5.0.3" "R-bundle-Bioconductor/3.20-R-4.4.2")

# --- Reference Base Paths ---
export REF_BASE="/scratch/tmp/thomachr/references"
export ARRIBA_BASE="/scratch/tmp/thomachr/arriba/arriba_v2.4.0"
export ARRIBA_DB="$ARRIBA_BASE/database"

# --- Specific Reference Files ---
export REF_GENOME="$ARRIBA_BASE/GRCh37viral.fa"
export STAR_INDEX="$ARRIBA_BASE/STAR_index_hs37d5viral_GENCODE19"
export STAR_INDEX_ARRIBA="$STAR_INDEX"

# Path to your newly indexed hg19 reference genome
export REF_GENOME_CNV="/scratch/tmp/jschnorr/references/hg19/hg19.fa"
export BWA_BIN="bwa-mem2"

export ANNOTATION_GTF="$ARRIBA_BASE/GENCODE19.gtf"
export ARRIBA_BLACKLIST="$ARRIBA_DB/blacklist_hg19_hs37d5_GRCh37_v2.4.0.tsv.gz"
export ARRIBA_KNOWN_FUSIONS="$ARRIBA_DB/known_fusions_hg19_hs37d5_GRCh37_v2.4.0.tsv.gz"
export ARRIBA_TAGS="$ARRIBA_KNOWN_FUSIONS"
export ARRIBA_PROTEIN_DOMAINS="$ARRIBA_DB/protein_domains_hg19_hs37d5_GRCh37_v2.4.0.gff3"
export ARRIBA_CYTOBANDS="$ARRIBA_DB/cytobands_hg19_hs37d5_GRCh37_v2.4.0.tsv"

# CNVkit & Custom Resources
export CNV_REFERENCE="$REF_BASE/panel_v4.1_reference.cnn"
export RELEVANT_GENES="$PROJECT_DIR/resources/relevant_genes.csv"
export CYTOBAND_TXT="$REF_BASE/cytoBand.txt"
export PANEL_REGIONS="$ARRIBA_BASE/coverage_regions.tsv"
export PANEL_BED="$PROJECT_DIR/resources/panel_v4.1_hg19.csv"

# --- Resource Allocation ---
export PIPELINE_THREADS=24
export PIPELINE_MEM="80G"
export PIPELINE_PARTITION="normal"
export SORT_MEM_BASE=20000

# --- Runtime & Output Paths ---
export SCRATCH_DIR="/scratch/tmp/$USER/ngs-tumor-pipeline"
export INPUT_DIR="$SCRATCH_DIR/input"
export VARIANTS_SEARCH_DIR="$SCRATCH_DIR/input"
export RESULTS_BASE="${RESULTS_BASE:-$SCRATCH_DIR/output}"
export VENV_PATH="$SCRATCH_DIR/env"