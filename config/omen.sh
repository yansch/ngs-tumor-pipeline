#!/bin/bash
# config/omen.sh - Omen-specific configuration

export HAS_MODULE_SYSTEM=false

# --- Path Additions ---
export PATH="/software/arriba_v2.5.1/bin:$PATH"

# --- Reference Base Paths ---
export BASE_DIR="/software/arriba_v2.5.1"
export REF_DIR="$BASE_DIR/references_hg19"
export ARRIBA_LIB="$BASE_DIR/var/lib/arriba"
export CNV_REF_DIR="/mnt/pipelines/ngs-tumor-pipeline/reference/cnv"

# --- Specific Reference Files ---
export REF_GENOME="$REF_DIR/hs37d5viral.fa"
export STAR_INDEX="$REF_DIR/STAR_index_hs37d5viral_GENCODE19"
export ANNOTATION_GTF="$REF_DIR/GENCODE19.gtf"
export ASSEMBLY_FA="$REF_DIR/hs37d5viral.fa"
export ARRIBA_BLACKLIST="$ARRIBA_LIB/blacklist_hg19_hs37d5_GRCh37_v2.5.1.tsv.gz"
export ARRIBA_KNOWN_FUSIONS="$ARRIBA_LIB/known_fusions_hg19_hs37d5_GRCh37_v2.5.1.tsv.gz"
export ARRIBA_TAGS="$ARRIBA_KNOWN_FUSIONS"
export ARRIBA_PROTEIN_DOMAINS="$ARRIBA_LIB/protein_domains_hg19_hs37d5_GRCh37_v2.5.1.gff3"
export ARRIBA_CYTOBANDS="$ARRIBA_LIB/cytobands_hg19_hs37d5_GRCh37_v2.5.1.tsv"

# CNVkit & Custom Resources
export CNV_REFERENCE="$CNV_REF_DIR/panel_v4.1_reference.cnn"
export RELEVANT_GENES="$CNV_REF_DIR/relevant_genes.csv"
export CYTOBAND_TXT="$CNV_REF_DIR/cytoBand.txt"
export PANEL_REGIONS="/mnt/pipelines/ngs-tumor-pipeline/reference/panel_v4.1_hg19.csv"

# --- Resource Allocation ---
export PIPELINE_THREADS=24
export PIPELINE_MEM="64G"
export SORT_MEM_BASE=20000

# --- Runtime & Output Paths ---
export SCRATCH_DIR="/data/ngs-tumor-pipeline/scratch"
export INPUT_DIR="/data/ngs-tumor-pipeline/input/fastq"
export VARIANTS_SEARCH_DIR="/data/ngs-tumor-pipeline/input/vcf"
export RESULTS_BASE="/data/ngs-tumor-pipeline/output"
export VENV_PATH="/mnt/pipelines/ngs-tumor-pipeline/env"
