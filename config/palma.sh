#!/bin/bash
# config/palma.sh - Palma-specific configuration

export HAS_MODULE_SYSTEM=true

# --- Toolchains (must be loaded before tool modules) ---
export TOOLCHAIN_BIO="palma/2022a"
export TOOLCHAIN_PYTHON="palma/2024a"

# --- Tool Modules (loaded after their toolchain) ---
export FASTP_MODULE="GCC/11.3.0 fastp/0.23.2"
export STAR_MODULE="GCC/11.3.0 STAR/2.7.10b"
export SAMTOOLS_MODULE="GCC/11.3.0 SAMtools/1.16.1"
export PYTHON_MODULE="GCCcore/13.3.0 Python/3.12.3"
export R_MODULE="palma/2024a GCC/13.3.0 OpenMPI/5.0.3 R/4.4.2"
export R_PYTHON_COMPAT_MODULE="palma/2024a GCC/13.3.0 OpenMPI/5.0.3 R-bundle-Bioconductor/3.20-R-4.4.2"
# jq/1.6 requires palma/2022b which conflicts with the default palma/2023b;
# the pipeline falls back to python3 for JSON parsing automatically.

# --- Reference Base Paths ---
export REF_BASE="/scratch/tmp/thomachr/references"
export ARRIBA_BASE="/scratch/tmp/thomachr/arriba/arriba_v2.4.0"
export ARRIBA_DB="$ARRIBA_BASE/database"

# --- Specific Reference Files ---
export REF_GENOME="$ARRIBA_BASE/GRCh37viral.fa"
export STAR_INDEX="$ARRIBA_BASE/STAR_index_GRCh37viral_GENCODE19"
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
export PIPELINE_MEM="64G"
export PIPELINE_TIME="00:30:00"
export PIPELINE_PARTITION="normal"
export SORT_MEM_BASE=20000

# --- Runtime & Output Paths ---
export SCRATCH_DIR="/scratch/tmp/$USER/ngs-tumor-pipeline"
export INPUT_DIR="$SCRATCH_DIR/input/fastq"
export VARIANTS_SEARCH_DIR="$SCRATCH_DIR/input/vcf"
export RESULTS_BASE="${RESULTS_BASE:-$SCRATCH_DIR/output}"
export VENV_PATH="$SCRATCH_DIR/env"
