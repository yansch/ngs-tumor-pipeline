#!/bin/bash
#SBATCH --nodes=1
#SBATCH --cpus-per-task=36
#SBATCH --partition normal
#SBATCH --time=0:30:00
#SBATCH --mem=80G
#SBATCH --job-name=ngs_pipeline
#SBATCH --mail-type=ALL
#SBATCH --error ./log/%x_%j.err.txt
#SBATCH --output ./log/%x_%j.out.txt

## Parameters ############################################################################
export PATH="/home/t/thomachr/bin:$PATH"
export PATH="/scratch/tmp/thomachr/software/krakenuniq:$PATH"
BASE_DIR=/scratch/tmp/thomachr/arriba/arriba_v2.4.0
RefGenome=/scratch/tmp/thomachr/references/hg19/hg19.fa
STAR_INDEX_DIR=$BASE_DIR/STAR_index_GRCh37viral_GENCODE19
ANNOTATION_GTF=$BASE_DIR/GENCODE19.gtf
ASSEMBLY_FA=$BASE_DIR/GRCh37viral.fa
BLACKLIST_TSV=$BASE_DIR/database/blacklist_hg19_hs37d5_GRCh37_v2.4.0.tsv.gz
KNOWN_FUSIONS_TSV=$BASE_DIR/database/known_fusions_hg19_hs37d5_GRCh37_v2.4.0.tsv.gz
TAGS_TSV="$KNOWN_FUSIONS_TSV" 
PROTEIN_DOMAINS_GFF3=$BASE_DIR/database/protein_domains_hg19_hs37d5_GRCh37_v2.4.0.gff3
DATABABASE=/scratch/tmp/thomachr/references/kraken/k2_standard_20230314
EUPATHDB=/scratch/tmp/thomachr/references/kraken/k2_eupathdb48_20230407
CNV_REF=/scratch/tmp/thomachr/references/panel_v4_reference.cnn
BOWTIE_INDEX=/scratch/tmp/thomachr/metagenomics/bowtie_index/GRCh38_noalt_as
MINIMAP_INDEX=/scratch/tmp/thomachr/references/GRCh38/GRCh38.mmi

THREADS=36
R1_base=`basename $1 .fastq.gz`
R2_base=`basename $2 .fastq.gz`
mkdir -p ./tmp
mkdir -p ./output
mkdir -p ./log
TMP_DIR=./tmp/${R1_base}
OUT_DIR=./output/${R1_base}
mkdir -p "$TMP_DIR"
mkdir -p "$OUT_DIR"
mkdir -p "$OUT_DIR"/cnv
mkdir -p "$OUT_DIR"/kraken
mkdir -p "$OUT_DIR"/fastqc
mkdir -p "$OUT_DIR"/fastp


# Run KrakenUniq
module purge
ml palma/2021b GCC/11.2.0 Jellyfish/2.3.0 bzip2/1.0.8

#krakenuniq \
#	--report-file "$OUT_DIR"/kraken/${R1_base}.krakenuniq.report.txt \
#	--db /scratch/tmp/thomachr/references/krakenuniq/microbial_db \
#	--threads $THREADS \
#	--output - \
#	--paired "$OUT_DIR"/${R1_base}_nonhuman_reads.fastq.gz "$OUT_DIR"/${R2_base}_nonhuman_reads.fastq.gz

module purge
ml palma/2021b  GCC/11.2.0  OpenMPI/4.1.1 Kraken2/2.1.2 Bracken/2.7

bracken \
	-d /scratch/tmp/thomachr/references/krakenuniq/microbial_db \
	-i "$OUT_DIR"/kraken/${R1_base}.krakenuniq.report.txt \
	-r 75 \
	-l S \
	-t 3 \
	-o "$OUT_DIR"/kraken/${R1_base}.krakenuniq.bracken_species.txt \
	-w "$OUT_DIR"/kraken/${R1_base}.krakenuniq.bracken_species.report.txt      

### Create summary report ###################################################################
#module purge
#ml palma/2023b GCC/13.2.0 R/4.4.1 Pandoc/3.1.2
#parent_dir=$(dirname "$1")
#sub_dir=$(dirname "$parent_dir")
#Rscript /home/t/thomachr/scripts/ngs_report.R $sub_dir/output/${R1_base} ${R1_base}