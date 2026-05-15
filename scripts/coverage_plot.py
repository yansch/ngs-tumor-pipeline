#!/usr/bin/env python3
import sys
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import subprocess
import os
import tempfile

import pysam

def get_all_depths_bedcov(bam_file, regions_df):
    """
    Calculate mean depth for all regions using 'pysam.samtools.bedcov' for maximum speed.
    """
    # Create temporary BED file
    with tempfile.NamedTemporaryFile(mode='w', suffix='.bed', delete=False) as tmp:
        for _, row in regions_df.iterrows():
            chrom = str(row['chr'])
            # Ensure 'chr' prefix to match BAM header (confirmed chr1, chr2, etc.)
            if not chrom.startswith('chr'):
                chrom = f"chr{chrom}"
            
            # Standard BED is 0-based start, half-open.
            # We'll assume the input is 1-based start, inclusive and convert to 0-based.
            tmp.write(f"{chrom}\t{int(row['start'])-1}\t{row['stop']}\n")
        tmp_path = tmp.name

    try:
        # pysam.samtools.bedcov returns the sum of depths for each region as a string
        # equivalent to 'samtools bedcov <bed> <bam>'
        output = pysam.samtools.bedcov(tmp_path, bam_file)
        
        # Parse output: last column is the sum of depths
        depth_sums = []
        for line in output.strip().split('\n'):
            if not line: continue
            parts = line.split('\t')
            # bedcov output format: chrom, start, end, ..., sum_depth
            start, end = int(parts[1]), int(parts[2])
            total_sum = int(parts[-1])
            length = end - start
            mean_depth = total_sum / length if length > 0 else 0
            depth_sums.append(mean_depth)
            
        return depth_sums
    except Exception as e:
        print(f"Error in pysam.samtools.bedcov: {e}")
        raise
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)

def main():
    if len(sys.argv) < 4:
        print("Usage: python coverage_plot.py <panel_file> <bam_file> <output_png> [output_txt]")
        sys.exit(1)
    
    panel_file = sys.argv[1]
    bam_file = sys.argv[2]
    out_png = sys.argv[3]
    
    print(f"Reading panel data from {panel_file}...")
    try:
        # Try reading as TSV first if it looks like one
        if panel_file.endswith('.tsv') or panel_file.endswith('.txt'):
            df = pd.read_csv(panel_file, sep='\t', header=None)
            if len(df.columns) >= 5:
                df.columns = ['chr', 'start', 'stop', 'Gene', 'Target'] + list(df.columns[5:])
                df['Type'] = 'Exon' # Fallback for logic below
            else:
                print(f"Error: TSV file {panel_file} has unexpected number of columns ({len(df.columns)})")
                sys.exit(1)
        else:
            # Assume CSV with header
            df = pd.read_csv(panel_file)
            if 'Type' not in df.columns:
                df['Type'] = 'Exon' # Assume Exon if missing
    except Exception as e:
        print(f"Error reading panel file: {e}")
        sys.exit(1)
        
    # Filter only Exons if Type exists
    if 'Type' in df.columns:
        df = df[df['Type'] == 'Exon'].copy()
    
    num_exons = len(df)
    print(f"Calculating mean depth for {num_exons} regions via samtools bedcov...")
    
    # Drop rows without required columns
    df = df.dropna(subset=['chr', 'start', 'stop', 'Target'])
    
    # Calculate all depths in one go
    try:
        all_depths = get_all_depths_bedcov(bam_file, df)
        
        records = []
        for i, (idx, row) in enumerate(df.iterrows()):
            records.append({
                'Gene': row['Gene'],
                'Target': row['Target'],
                'Coverage': all_depths[i],
                'chr': row['chr'],
                'start': row['start']
            })
    except Exception as e:
        print(f"Error calculating coverage: {e}")
        sys.exit(1)
    
    cov_df = pd.DataFrame(records)
    
    if cov_df.empty:
        print("Error: No coverage data generated.")
        sys.exit(1)
        
    # Set default values if Gene is missing
    cov_df.loc[:, 'Gene'] = cov_df['Gene'].fillna("Unknown")
    
    # Sort for plotting: Group by Gene, then by Target Name
    cov_df = cov_df.sort_values(by=['Gene', 'Target'])
    
    print("Generating plot...")
    # --- Custom Coordinate System for Genealogical Spacing ---
    x_coords = []
    current_x = 0.0
    inter_gap = 2.0 # gap between different genes
    
    all_gene_labels = []
    all_gene_positions = []
    all_gene_boundaries = []
    
    palette = sns.color_palette("Set1", 9) + sns.color_palette("Set2", 8) + sns.color_palette("Dark2", 8)
    gene_colors = []
    color_idx = -1
    
    current_gene = None
    gene_start_x = 0.0
    
    for i, (idx, row) in enumerate(cov_df.iterrows()):
        if row['Gene'] != current_gene:
            if current_gene is not None:
                all_gene_labels.append(current_gene)
                all_gene_positions.append((gene_start_x + current_x - 1.0) / 2.0)
                all_gene_boundaries.append(current_x - (inter_gap / 2.0))
                current_x += inter_gap
            
            current_gene = row['Gene']
            gene_start_x = current_x
            color_idx = (color_idx + 1) % len(palette)
            
        x_coords.append(current_x)
        gene_colors.append(palette[color_idx])
        current_x += 1.0
        
    all_gene_labels.append(current_gene)
    all_gene_positions.append((gene_start_x + current_x - 1.0) / 2.0)

    # Split into two subplots if many genes
    num_genes = len(all_gene_labels)
    if num_genes > 10:
        fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(16, 10), dpi=300)
        split_gene_idx = num_genes // 2
        split_coord = all_gene_boundaries[split_gene_idx - 1]
        split_row_idx = 0
        for i, xc in enumerate(x_coords):
            if xc > split_coord:
                split_row_idx = i
                break
    else:
        fig, ax1 = plt.subplots(1, 1, figsize=(16, 6), dpi=300)
        ax2 = None
        split_row_idx = len(cov_df)

    max_coverage = cov_df['Coverage'].max()
    y_limit = max(100, max_coverage * 1.15)
        
    def plot_subset(ax, start_row, end_row):
        if ax is None: return
        sub_df = cov_df.iloc[start_row:end_row]
        sub_x = x_coords[start_row:end_row]
        sub_colors = gene_colors[start_row:end_row]
        
        offset = sub_x[0]
        sub_x_offset = [xc - offset for xc in sub_x]
        
        ax.bar(sub_x_offset, sub_df['Coverage'], color=sub_colors, width=1.0, edgecolor='black', linewidth=0.1)
        
        sub_gene_labels = []
        sub_gene_positions = []
        for label, pos in zip(all_gene_labels, all_gene_positions):
            if sub_x[0] <= pos <= sub_x[-1]:
                sub_gene_labels.append(label)
                sub_gene_positions.append(pos - offset)
        
        for b in all_gene_boundaries:
            if sub_x[0] < b < sub_x[-1]:
                ax.axvline(b - offset, color='black', linestyle='--', linewidth=0.5, alpha=0.3)
                
        ax.set_xticks(sub_gene_positions)
        ax.set_xticklabels(sub_gene_labels, rotation=45, fontsize=10, ha='right')
        ax.set_ylabel('Mean Depth (X)', fontsize=11)
        ax.set_ylim(0, y_limit)
        ax.grid(axis='y', linestyle=':', alpha=0.6)
        ax.set_xlim(-1, sub_x_offset[-1] + 1)

    plot_subset(ax1, 0, split_row_idx)
    if ax2:
        plot_subset(ax2, split_row_idx, len(cov_df))
    
    plt.tight_layout()
    print(f"Saving plot to {out_png}...")
    plt.savefig(out_png, dpi=300, bbox_inches='tight')
    plt.close()

    # Data Export (.txt)
    if len(sys.argv) > 4:
        out_txt = sys.argv[4]
        print(f"Saving coverage data to {out_txt}...")
        cov_df[['chr', 'start', 'Coverage', 'Gene', 'Target']].to_csv(out_txt, sep='\t', index=False, header=False)

    print("Done!")

if __name__ == "__main__":
    main()
