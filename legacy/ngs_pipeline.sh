#!/bin/bash
#SBATCH --nodes=1
#SBATCH --cpus-per-task=36
#SBATCH --partition normal
#SBATCH --time=1:30:00
#SBATCH --mem=80G
#SBATCH --job-name=ngs_pipeline
#SBATCH --mail-type=ALL
#SBATCH --error ./log/%x_%j.err.txt
#SBATCH --output ./log/%x_%j.out.txt

# Stop script execution on error, unset variables, and piping errors
set -euo pipefail

# Input Validation
if [ "$#" -lt 2 ]; then
    echo "Error: Two input fastq.gz files are required."
    echo "Usage: sbatch $0 <R1.fastq.gz> <R2.fastq.gz>"
    exit 1
fi

## Parameters ############################################################################
export PATH="/home/t/thomachr/bin:$PATH"
export PATH="/scratch/tmp/thomachr/software/krakenuniq:$PATH"

BASE_DIR=/scratch/tmp/thomachr/arriba/arriba_v2.4.0
RefGenome=/scratch/tmp/thomachr/references/hg19/hg19.fa
STAR_INDEX_DIR="$BASE_DIR"/STAR_index_GRCh37viral_GENCODE19
ANNOTATION_GTF="$BASE_DIR"/GENCODE19.gtf
ASSEMBLY_FA="$BASE_DIR"/GRCh37viral.fa
BLACKLIST_TSV="$BASE_DIR"/database/blacklist_hg19_hs37d5_GRCh37_v2.4.0.tsv.gz
KNOWN_FUSIONS_TSV="$BASE_DIR"/database/known_fusions_hg19_hs37d5_GRCh37_v2.4.0.tsv.gz
TAGS_TSV="$KNOWN_FUSIONS_TSV"
PROTEIN_DOMAINS_GFF3="$BASE_DIR"/database/protein_domains_hg19_hs37d5_GRCh37_v2.4.0.gff3
DATABASE=/scratch/tmp/thomachr/references/krakenuniq/microbial_db
CNV_REF=/scratch/tmp/thomachr/references/panel_v4.1_reference.cnn
BOWTIE_INDEX=/scratch/tmp/thomachr/metagenomics/bowtie_index/GRCh38_noalt_as
MINIMAP_INDEX=/scratch/tmp/thomachr/references/GRCh38/GRCh38.mmi

THREADS=36
R1_base=$(basename "$1" .fastq.gz)
R2_base=$(basename "$2" .fastq.gz)

TMP_DIR="./tmp/${R1_base}"
OUT_DIR="./output/${R1_base}"
CNV_DIR="$OUT_DIR/cnv"

# Combined directory creation
mkdir -p "$TMP_DIR" "$CNV_DIR" "$OUT_DIR"/{kraken,fastqc,fastp,arriba,nonhuman_reads} log

# Helper function to prevent python env module repetition
load_ngs_python_env() {
    module purge
    ml palma/2024a GCC/13.3.0 Python/3.12.3 SciPy-bundle/2024.05 matplotlib/3.9.2
    source /home/t/thomachr/python-envs/ngs-reporting/bin/activate
}

### Trimming and QC ###########################################################################
ml palma/2022a GCC/11.3.0 fastp/0.23.2
fastp -i "$1" -I "$2" -o "$TMP_DIR/${R1_base}.trimmed.fq.gz" -O "$TMP_DIR/${R2_base}.trimmed.fq.gz" \
    -p "$THREADS" --low_complexity_filter -h "$OUT_DIR/fastp/${R1_base}.fastp.html" -j /dev/null

module purge
ml palma/2019a FastQC/0.11.9-Java-11
fastqc --extract -t "$THREADS" -o "$OUT_DIR/fastqc" "$1" "$2"
fastqc --extract -t "$THREADS" -o "$OUT_DIR/fastqc" "$TMP_DIR"/*.trimmed.fq.gz


### Alignment with BWA (Streamlined) ##################################################
module purge
ml palma/2019a GCC/8.2.0-2.31.1 BWA/0.7.17
ml palma/2022a GCC/11.3.0 SAMtools/1.16.1

# BWA -> sort directly into BAM (Saves multiple intermediate file writes)
bwa mem -t "$THREADS" "$RefGenome" "$1" "$2" | \
    samtools sort -@ "$THREADS" -m $((40000/THREADS))M -T "$TMP_DIR/bwa_tmp" -o "$TMP_DIR/${R1_base}_aligned_sorted.bam"

samtools index "$TMP_DIR/${R1_base}_aligned_sorted.bam"


### CNV calling with CNVkit ################################################################
module purge
ml palma/2022b foss/2022b CNVkit/0.9.10-R-4.2.2

cnvkit.py batch "$TMP_DIR/${R1_base}_aligned_sorted.bam" --reference "$CNV_REF" --processes 0 \
    --drop-low-coverage --output-dir "$CNV_DIR" --diagram

# CNVkit sex call using reference and intermediate .cnn files
# (Arrays used instead of ls to handle paths robustly and avoid subshell overhead)
target_cnns=("$CNV_DIR"/*.targetcoverage.cnn)
antitarget_cnns=("$CNV_DIR"/*.antitargetcoverage.cnn)

cnvkit.py sex "$CNV_REF" "${target_cnns[0]}" "${antitarget_cnns[0]}" -o "$CNV_DIR/${R1_base}_sex.txt"

CNR_FILE="$CNV_DIR/${R1_base}_aligned_sorted.cnr"
CNS_FILE="$CNV_DIR/${R1_base}_aligned_sorted.cns"

for chr in {1..22}; do
    gene_args=""
    case $chr in
        4)  gene_args="-g PDGFRA,FGFR3" ;;
        7)  gene_args="-g EGFR,MET" ;;
        8)  gene_args="-g FGFR1" ;;
        9)  gene_args="-g CDKN2A" ;;
        10) gene_args="-g PTEN" ;;
        17) gene_args="-g TP53" ;;
        22) gene_args="-g SMARCB1" ;;
    esac

    echo "Plotting CNV scatter for chr${chr}..."
    cnvkit.py scatter "$CNR_FILE" \
        -s "$CNS_FILE" \
        -c "chr${chr}" \
        --segment-color 'purple' \
        $gene_args \
        -o "$CNV_DIR/${R1_base}_chr${chr}.png" || true # prevent script death if region is empty
done

cp "$CNV_DIR/${R1_base}_chr7.png" "$CNV_DIR/EGFR_MET.png"
cp "$CNV_DIR/${R1_base}_chr9.png" "$CNV_DIR/CDKN2A.png"

load_ngs_python_env

for p_int in {10..1}; do
    if [ "$p_int" -eq 10 ]; then
        purity="1.0"
        fname="cnv_plot.png"
    else
        purity="0.$p_int"
        fname="cnv_plot_purity_${purity}.png"
    fi
    echo "Generating CNV plot for purity ${purity}..."
    python /home/t/thomachr/scripts/plot_cnv_from_ngs.py "$OUT_DIR/cnv"/*aligned_sorted.cnr --case-id "${R1_base}" -o "$OUT_DIR/cnv" -f "$fname" --purity "$purity" -c /home/t/thomachr/scripts/cnv_static/cytoBand.txt -g /home/t/thomachr/scripts/cnv_static/relevant_genes.csv
done


### Arriba #################################################################################
module purge
ml palma/2022a GCC/11.3.0 SAMtools/1.16.1 OpenMPI/4.1.4 R-bundle-Bioconductor/3.15-R-4.2.1

# Use process substitution '>()' to stream into Arriba and samtools sort simultaneously
/scratch/tmp/thomachr/software/STAR-2.7.10b/source/STAR \
    --runThreadN "$THREADS" \
    --outFileNamePrefix "$TMP_DIR/" \
    --genomeDir "$STAR_INDEX_DIR" --genomeLoad NoSharedMemory \
    --readFilesIn "$1" "$2" --readFilesCommand zcat \
    --outStd BAM_Unsorted --outSAMtype BAM Unsorted --outSAMunmapped Within --outBAMcompression 0 \
    --outFilterMultimapNmax 50 --peOverlapNbasesMin 10 --alignSplicedMateMapLminOverLmate 0.5 --alignSJstitchMismatchNmax 5 -1 5 5 \
    --chimSegmentMin 10 --chimOutType WithinBAM HardClip --chimJunctionOverhangMin 10 --chimScoreDropMax 30 --chimScoreJunctionNonGTAG 0 --chimScoreSeparation 1 --chimSegmentReadGapMax 3 --chimMultimapNmax 50 | \
tee >( "$BASE_DIR/arriba" \
    -x /dev/stdin -I \
    -o "$OUT_DIR/arriba/${R1_base}_fusions.tsv" -f intronic,in_vitro,internal_tandem_duplication \
    -a "$ASSEMBLY_FA" -g "$ANNOTATION_GTF" -b "$BLACKLIST_TSV" -k "$KNOWN_FUSIONS_TSV" -t "$TAGS_TSV" -p "$PROTEIN_DOMAINS_GFF3" ) | \
samtools sort -@ "$THREADS" -m $((40000/THREADS))M -T "$TMP_DIR/star_tmp" -O bam -o "$TMP_DIR/${R1_base}_Aligned.sortedByCoord.out.bam"

samtools index "$TMP_DIR/${R1_base}_Aligned.sortedByCoord.out.bam"

samtools depth -d 0 -b "$BASE_DIR/coverage_regions.tsv" "$TMP_DIR/${R1_base}_Aligned.sortedByCoord.out.bam" > "$CNV_DIR/${R1_base}_panel_coverage.txt"

"$BASE_DIR/draw_fusions.R" \
    --fusions="$OUT_DIR/arriba/${R1_base}_fusions.tsv" \
    --alignments="$TMP_DIR/${R1_base}_Aligned.sortedByCoord.out.bam" \
    --output="$OUT_DIR/arriba/${R1_base}_fusions.pdf" \
    --annotation="$ANNOTATION_GTF" \
    --cytobands="$BASE_DIR/database/cytobands_hg19_hs37d5_GRCh37_v2.4.0.tsv" \
    --proteinDomains="$PROTEIN_DOMAINS_GFF3"

"$BASE_DIR/scripts/quantify_virus_expression.sh" "$TMP_DIR/${R1_base}_Aligned.sortedByCoord.out.bam" "$OUT_DIR/arriba/${R1_base}virus_expression.tsv"

load_ngs_python_env

python /home/t/thomachr/scripts/arriba/coverage_plot.py \
    "$BASE_DIR/coverage_regions.tsv" \
    "$CNV_DIR/${R1_base}_panel_coverage.txt" \
    "$CNV_DIR/${R1_base}_panel_coverage.png"

### Metagenomics ######################################################################
# Host removal with Bowtie2
module purge
ml palma/2020b GCC/10.2.0 Bowtie2/2.4.2

bowtie2 -x "$BOWTIE_INDEX" -p "$THREADS" -1 "$TMP_DIR/${R1_base}.trimmed.fq.gz" \
    -2 "$TMP_DIR/${R2_base}.trimmed.fq.gz" \
    --un-conc-gz "$TMP_DIR/${R1_base}_nonhuman_reads" \
    -S /dev/null # Sending SAM output to /dev/null completely eliminates huge disk writes

mv "$TMP_DIR/${R1_base}_nonhuman_reads.1" "$OUT_DIR/nonhuman_reads/${R1_base}_nonhuman_reads.fastq.gz"
mv "$TMP_DIR/${R1_base}_nonhuman_reads.2" "$OUT_DIR/nonhuman_reads/${R2_base}_nonhuman_reads.fastq.gz"

# Run KrakenUniq
module purge
ml palma/2021b GCC/11.2.0 Jellyfish/2.3.0 bzip2/1.0.8

krakenuniq \
    --report-file "$OUT_DIR/kraken/${R1_base}.krakenuniq.report.txt" \
    --db "$DATABASE" \
    --threads "$THREADS" \
    --output - \
    --paired "$OUT_DIR/nonhuman_reads/${R1_base}_nonhuman_reads.fastq.gz" "$OUT_DIR/nonhuman_reads/${R2_base}_nonhuman_reads.fastq.gz"

load_ngs_python_env

# Fixed OUT_DIR reference
python /home/t/jschnorr/scripts/ngs_report.py "$OUT_DIR" "${R1_base}"
