#!/bin/bash
#SBATCH --nodes=1
#SBATCH --cpus-per-task=36
#SBATCH --partition normal
#SBATCH --time=1:30:00
#SBATCH --mem=80G
#SBATCH --job-name=cnv_pipeline
#SBATCH --mail-type=ALL
#SBATCH --error ./log/%x_%j.err.txt
#SBATCH --output ./log/%x_%j.out.txt

# This script performs CNV analysis using CNVkit from paired-end FASTQ files.
# It first aligns reads to a reference genome using BWA and then uses the
# resulting BAM file to call copy number variations.

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error.

## Parameters ############################################################################
# --- Essential Paths ---
# Path to the reference genome for alignment
RefGenome=/scratch/tmp/thomachr/references/hg19/hg19.fa
# Path to the CNVkit reference file (.cnn)
CNV_REF=/scratch/tmp/thomachr/references/panel_v4_reference.cnn

# --- Resources ---
THREADS=36

## Input & Output Setup ##################################################################
# Check if input files are provided
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Error: Please provide paths to R1 and R2 FASTQ files."
    echo "Usage: $0 <path/to/read1.fastq.gz> <path/to/read2.fastq.gz>"
    exit 1
fi

R1_FASTQ="$1"
R2_FASTQ="$2"

R1_base=$(basename "$R1_FASTQ" .fastq.gz)

# Create output directories
echo "Setting up directories..."
mkdir -p ./tmp
mkdir -p ./output
mkdir -p ./log

TMP_DIR=./tmp/${R1_base}
OUT_DIR=./output/${R1_base}

mkdir -p "$TMP_DIR"
mkdir -p "$OUT_DIR"

echo "Temporary directory: $TMP_DIR"
echo "Output directory: $OUT_DIR"

## Alignment with BWA ###################################################################
echo "Step 1: Aligning reads with BWA-MEM..."
module purge
ml palma/2019a GCC/8.2.0-2.31.1 BWA/0.7.17
bwa mem -t $THREADS "$RefGenome" "$R1_FASTQ" "$R2_FASTQ" > "$TMP_DIR"/${R1_base}_aligned.sam

echo "Step 2: Converting SAM to BAM, sorting, and indexing..."
module purge
ml palma/2022a GCC/11.3.0 SAMtools/1.16.1

samtools view -@ "$THREADS" -S -b "$TMP_DIR"/${R1_base}_aligned.sam > "$TMP_DIR"/${R1_base}_aligned.bam
samtools sort -@ "$THREADS" -m 2G -T "$TMP_DIR"/tmp_sort -O bam "$TMP_DIR"/${R1_base}_aligned.bam -o "$TMP_DIR"/${R1_base}_aligned_sorted.bam
samtools index "$TMP_DIR"/${R1_base}_aligned_sorted.bam

rm "$TMP_DIR"/${R1_base}_aligned.sam
rm "$TMP_DIR"/${R1_base}_aligned.bam
echo "Alignment and processing complete."

## CNV calling with CNVkit ###############################################################
echo "Step 3: Calling CNVs with CNVkit..."
module purge
ml palma/2022b foss/2022b CNVkit/0.9.10-R-4.2.2

# Run the CNVkit batch command for a single tumor sample against a reference
cnvkit.py batch "$TMP_DIR"/${R1_base}_aligned_sorted.bam \
    --reference "$CNV_REF" \
    --processes "$THREADS" \
    --drop-low-coverage \
    --output-dir "$OUT_DIR" \
    --diagram

echo "Step 4: Generating CNV scatter plots..."
# Plot whole-genome scatter plot
cnvkit.py scatter -s "$OUT_DIR"/*_aligned_sorted.cn{s,r} \
    --segment-color 'blue' --fig-size 10 4 --y-min "-2" --y-max "4" \
    -o "$OUT_DIR"/cnv_plot_cnvkit.pdf

# Generate per-chromosome plots
cnvkit.py scatter -s "$OUT_DIR"/*_aligned_sorted.cn{s,r} -c chr1 --segment-color 'blue' -o "$OUT_DIR"/${R1_base}_chr1.pdf
cnvkit.py scatter -s "$OUT_DIR"/*_aligned_sorted.cn{s,r} -c chr2 --segment-color 'blue' -o "$OUT_DIR"/${R1_base}_chr2.pdf
cnvkit.py scatter -s "$OUT_DIR"/*_aligned_sorted.cn{s,r} -c chr3 --segment-color 'blue' -o "$OUT_DIR"/${R1_base}_chr3.pdf
cnvkit.py scatter -s "$OUT_DIR"/*_aligned_sorted.cn{s,r} -c chr4 --segment-color 'blue' -g PDGFRA,FGFR3 -o "$OUT_DIR"/${R1_base}_chr4.pdf
cnvkit.py scatter -s "$OUT_DIR"/*_aligned_sorted.cn{s,r} -c chr5 --segment-color 'blue' -o "$OUT_DIR"/${R1_base}_chr5.pdf
cnvkit.py scatter -s "$OUT_DIR"/*_aligned_sorted.cn{s,r} -c chr6 --segment-color 'blue' -o "$OUT_DIR"/${R1_base}_chr6.pdf
cnvkit.py scatter -s "$OUT_DIR"/*_aligned_sorted.cn{s,r} -c chr7 --segment-color 'blue' -g EGFR,MET -o "$OUT_DIR"/${R1_base}_chr7.pdf

cnvkit.py scatter -s "$OUT_DIR"/*_aligned_sorted.cn{s,r} -c chr8 --segment-color 'blue' -g FGFR1 -o "$OUT_DIR"/${R1_base}_chr8.pdf
cnvkit.py scatter -s "$OUT_DIR"/*_aligned_sorted.cn{s,r} -c chr9 --segment-color 'blue' -g CDKN2A -o "$OUT_DIR"/${R1_base}_chr9.pdf

cnvkit.py scatter -s "$OUT_DIR"/*_aligned_sorted.cn{s,r} -c chr10 --segment-color 'blue' -g PTEN -o "$OUT_DIR"/${R1_base}_chr10.pdf
cnvkit.py scatter -s "$OUT_DIR"/*_aligned_sorted.cn{s,r} -c chr11 --segment-color 'blue' -o "$OUT_DIR"/${R1_base}_chr11.pdf
cnvkit.py scatter -s "$OUT_DIR"/*_aligned_sorted.cn{s,r} -c chr12 --segment-color 'blue' -o "$OUT_DIR"/${R1_base}_chr12.pdf
cnvkit.py scatter -s "$OUT_DIR"/*_aligned_sorted.cn{s,r} -c chr13 --segment-color 'blue' -o "$OUT_DIR"/${R1_base}_chr13.pdf
cnvkit.py scatter -s "$OUT_DIR"/*_aligned_sorted.cn{s,r} -c chr14 --segment-color 'blue' -o "$OUT_DIR"/${R1_base}_chr14.pdf
cnvkit.py scatter -s "$OUT_DIR"/*_aligned_sorted.cn{s,r} -c chr15 --segment-color 'blue' -o "$OUT_DIR"/${R1_base}_chr15.pdf
cnvkit.py scatter -s "$OUT_DIR"/*_aligned_sorted.cn{s,r} -c chr16 --segment-color 'blue' -o "$OUT_DIR"/${R1_base}_chr16.pdf
cnvkit.py scatter -s "$OUT_DIR"/*_aligned_sorted.cn{s,r} -c chr17 --segment-color 'blue' -g TP53 -o "$OUT_DIR"/${R1_base}_chr17.pdf
cnvkit.py scatter -s "$OUT_DIR"/*_aligned_sorted.cn{s,r} -c chr18 --segment-color 'blue' -o "$OUT_DIR"/${R1_base}_chr18.pdf
cnvkit.py scatter -s "$OUT_DIR"/*_aligned_sorted.cn{s,r} -c chr19 --segment-color 'blue' -o "$OUT_DIR"/${R1_base}_chr19.pdf
cnvkit.py scatter -s "$OUT_DIR"/*_aligned_sorted.cn{s,r} -c chr20 --segment-color 'blue' -o "$OUT_DIR"/${R1_base}_chr20.pdf
cnvkit.py scatter -s "$OUT_DIR"/*_aligned_sorted.cn{s,r} -c chr21 --segment-color 'blue' -o "$OUT_DIR"/${R1_base}_chr21.pdf
cnvkit.py scatter -s "$OUT_DIR"/*_aligned_sorted.cn{s,r} -c chr22 --segment-color 'blue' -g SMARCB1 -o "$OUT_DIR"/${R1_base}_chr22.pdf

## Final Custom Plotting #################################################################
### ! Important: adjust absolute paths as necessary
echo "Step 5: Generating final plot..."
module purge
ml palma/2024a GCC/13.3.0 matplotlib/3.9.2
python /home/j/jschnorr/scripts/plot_cnv_from_ngs.py \
    "$OUT_DIR"/*_aligned_sorted.cnr \
    -o "$OUT_DIR" \
    -f 'cnv_plot.png' \
    -c /home/j/jschnorr/scripts/input/static/cytoBand.txt \
    -g /home/j/jschnorr/scripts/input/static/relevant_genes.csv

echo "CNV analysis pipeline finished."