#!/bin/bash
# config.sh - Centralized configuration for NGS Tumor Pipeline

# --- Tool Versions & Modules ---
export FASTP_MODULE="palma/2022a GCC/11.3.0 fastp/0.23.2"
export STAR_MODULE="palma/2022a GCC/11.3.0 STAR/2.7.10b"
export SAMTOOLS_MODULE="palma/2022a GCC/11.3.0 SAMtools/1.16.1"
export PYTHON_MODULE="palma/2023b GCCcore/13.2.0 Python/3.11.5"
export R_MODULE="palma/2022a GCC/11.3.0 R/4.2.1"
export R_PYTHON_COMPAT_MODULE="palma/2023b GCC/13.2.0 OpenMPI/4.1.6 R-bundle-Bioconductor/3.19-R-4.4.1"

# --- Reference Base Paths (Shared) ---
export REF_BASE="/scratch/tmp/thomachr/references"
export ARRIBA_BASE="/scratch/tmp/thomachr/arriba/arriba_v2.4.0"
export ARRIBA_DB="$ARRIBA_BASE/database"

# --- Specific Reference Files ---
export REF_GENOME="$ARRIBA_BASE/GRCh37viral.fa" # Matches the STAR index assembly
export STAR_INDEX="$ARRIBA_BASE/STAR_index_GRCh37viral_GENCODE19"
export ANNOTATION_GTF="$ARRIBA_BASE/GENCODE19.gtf"

# Arriba Databases
export ARRIBA_BLACKLIST="$ARRIBA_DB/blacklist_hg19_hs37d5_GRCh37_v2.4.0.tsv.gz"
export ARRIBA_KNOWN_FUSIONS="$ARRIBA_DB/known_fusions_hg19_hs37d5_GRCh37_v2.4.0.tsv.gz"
export ARRIBA_PROTEIN_DOMAINS="$ARRIBA_DB/protein_domains_hg19_hs37d5_GRCh37_v2.4.0.gff3"
export ARRIBA_CYTOBANDS="$ARRIBA_DB/cytobands_hg19_hs37d5_GRCh37_v2.4.0.tsv"

# CNVkit & Custom Resources
export CNV_REFERENCE="$REF_BASE/panel_v4.1_reference.cnn"
export RELEVANT_GENES="$PROJECT_DIR/resources/relevant_genes.csv"
export CYTOBAND_TXT="$REF_BASE/cytoBand.txt"
export PANEL_REGIONS="$ARRIBA_BASE/coverage_regions.tsv"
 
# --- Resource Allocation ---
export PIPELINE_THREADS=36
export PIPELINE_MEM="128G"

# --- Runtime & Output Paths ---
export PROJECT_DIR="/home/j/jschnorr/ngs_tumor_pipeline"
export SCRATCH_DIR="/scratch/tmp/jschnorr/ngs_tumor_pipeline"
export RESULTS_BASE="${RESULTS_BASE:-$SCRATCH_DIR/output}"
export VENV_PATH="$SCRATCH_DIR/env"
