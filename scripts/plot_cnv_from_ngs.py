#!/usr/bin/env python
# -*- coding: utf-8 -*-

import argparse
from pathlib import Path
import sys
import re
from os import path

import numpy as np
import pandas as pd
from intervaltree import IntervalTree
from matplotlib import pyplot as plt
from scipy.stats import zscore

DEFAULT_PLOT_Y_LIM = 7.5
GENE_ANNOTATION_PADDING = 0
GENE_MERGE_DISTANCE = 2_000_000

# Default paths
DEFAULT_CYTOBAND_PATH = Path('input/static/cytoBand.txt')
DEFAULT_RELEVANT_GENES_PATH = Path('input/static/relevant_genes.csv')
DEFAULT_OUTPUT_DIR = Path('output')

# Column definitions
CYTOBAND_COLUMN_NAMES = ['chromosome', 'start', 'end', 'band', 'giemsa']
RELEVANT_GENES_COLUMN_NAMES = ['gene', 'chromosome', 'start', 'end']


def natural_sort_key_chromosome(chrom_str):
    """
    Sort key for chromosome strings (e.g., 'chr1', 'chr2', 'chr10', 'chrX', 'chrY', 'chrM').
    'chr' prefix is handled. Numeric parts are treated as integers.
    X, Y, M are placed after numeric chromosomes.
    """
    s = str(chrom_str)  # Ensure it's a string
    name = s.lower().replace('chr', '')
    if name == 'x':
        return (1, 100)  # Main group 1 for autosomes/sex, then order within
    if name == 'y':
        return (1, 101)

    # For numeric chromosomes, try to extract number
    match = re.match(r'^(\d+)(.*)', name)  # Match numeric part and any suffix
    if match:
        numeric_part = int(match.group(1))
        suffix_part = match.group(2)  # e.g. 'p', 'q' or empty
        # Prioritize pure numeric, then with suffixes
        return (0, numeric_part, suffix_part)

    # Fallback for other non-standard chromosome names (sort alphabetically within a later group)
    return (2, s)


def extract_case_identifier(filepath: Path) -> str:
    """Extracts a base identifier from the input filename."""
    return filepath.stem.split('.')[0]


def load_and_preprocess_cytoband(file_path):
    """Loads cytoband data and ensures chromosome column is string."""
    try:
        df = pd.read_csv(file_path, delimiter='\t', names=CYTOBAND_COLUMN_NAMES)
        df.loc[:, 'chromosome'] = df['chromosome'].astype(str)  # Ensure string type
    except FileNotFoundError:
        print(f"Error: Cytoband file not found at {file_path}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error loading cytoband file {file_path}: {e}", file=sys.stderr)
        sys.exit(1)
    return df


def calculate_chromosome_features(cytoband_df):
    """Calculates chromosome lengths, absolute starts, and p/q arm boundaries."""
    if cytoband_df.empty:
        print("Warning: Cytoband data is empty, cannot calculate chromosome features.", file=sys.stderr)
        return pd.DataFrame(columns=['chromosome', 'length', 'chromosome_absolute_start']), {}, []

    # Ensure chromosome column is string before grouping
    cytoband_df.loc[:, 'chromosome'] = cytoband_df['chromosome'].astype(str)

    chromosomes_df = (
        cytoband_df
        .groupby('chromosome')
        .agg(length=('end', 'max'))
        .reset_index()
    )
    chromosomes_df['sort_key'] = chromosomes_df['chromosome'].apply(natural_sort_key_chromosome)
    chromosomes_df = chromosomes_df.sort_values('sort_key').drop(columns=['sort_key']).reset_index(drop=True)

    chromosomes_df['chromosome_absolute_start'] = chromosomes_df['length'].cumsum() - chromosomes_df['length']
    chromosome_start_map = chromosomes_df.set_index('chromosome')['chromosome_absolute_start'].to_dict()

    # Find the end of the p-arm (centromere start) for each chromosome.
    arm_boundaries = []
    p_arm_data = cytoband_df[cytoband_df['band'].str.startswith('p', na=False)]
    if not p_arm_data.empty:
        p_arm_ends = p_arm_data.groupby('chromosome').agg(p_arm_end_pos=('end', 'max'))

        # Calculate the absolute genomic position for each boundary
        for chrom, row in p_arm_ends.iterrows():
            if chrom in chromosome_start_map:
                absolute_boundary = chromosome_start_map[chrom] + row['p_arm_end_pos']
                arm_boundaries.append(absolute_boundary)

    return chromosomes_df, chromosome_start_map, arm_boundaries


def load_and_preprocess_relevant_genes(file_path):
    """Loads relevant genes data and ensures chromosome column is string."""
    try:
        df = pd.read_csv(file_path, delimiter=';', names=RELEVANT_GENES_COLUMN_NAMES)
        df.loc[:, 'chromosome'] = df['chromosome'].astype(str)  # Ensure string type
    except FileNotFoundError:
        print(f"Warning: Relevant genes file not found at {file_path}. Gene annotation will be skipped.",
              file=sys.stderr)
        return pd.DataFrame()
    except Exception as e:
        print(f"Error loading relevant genes file {file_path}: {e}", file=sys.stderr)
        return pd.DataFrame()
    return df


def build_gene_interval_trees(relevant_genes_df):
    """Builds a dictionary of IntervalTrees for gene lookups, per chromosome (string keys)."""
    if relevant_genes_df.empty:
        return {}
    trees = {}
    # Ensure chromosome is string type for grouping
    relevant_genes_df.loc[:, 'chromosome'] = relevant_genes_df['chromosome'].astype(str)
    relevant_genes_df = relevant_genes_df.dropna(subset=['chromosome'])

    for chrom, group in relevant_genes_df.groupby('chromosome'):
        tree = IntervalTree()
        for _, row in group.iterrows():
            start = int(row.start)
            end = int(row.end)
            tree.addi(start, end + 1, {'gene': row.gene, 'start': start, 'end': end})
        trees[chrom] = tree
    return trees


def load_ngs_cnr_file(cnr_filepath, case_identifier):
    """
    Loads a single .cnr file, adds case identifier, preprocesses,
    and returns the DataFrame along with the mean and std of its original log2 values.
    Ensures chromosome column is string type.
    """
    if not cnr_filepath.exists():
        print(f"Error: Input .cnr file not found at {cnr_filepath}", file=sys.stderr)
        return None, np.nan, np.nan

    try:
        df = pd.read_csv(cnr_filepath, sep='\t')
        # Ensure chromosome column is string type right after loading
        if 'chromosome' in df.columns:
            df.loc[:, 'chromosome'] = df['chromosome'].astype(str)
        else:
            print(f"Error: 'chromosome' column not found in {cnr_filepath.name}", file=sys.stderr)
            return None, np.nan, np.nan

    except Exception as e:
        print(f"Error reading .cnr file {cnr_filepath}: {e}", file=sys.stderr)
        return None, np.nan, np.nan

    df.loc[:, 'case_identifier'] = case_identifier

    if df.empty:
        print(f"Warning: No data in {cnr_filepath.name} after initial load.", file=sys.stderr)
        return None, np.nan, np.nan

    for col in ['start', 'end']:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors='coerce').astype(pd.Int64Dtype())

    df = df.dropna(subset=['chromosome', 'start', 'end', 'log2'])
    if df.empty:
        print(f"Warning: No data left in {cnr_filepath.name} after dropping NaNs in key columns (incl. log2).",
              file=sys.stderr)
        return None, np.nan, np.nan

    is_antitarget = (df['gene'] == 'Antitarget')
    df.loc[is_antitarget, 'gene'] = pd.NA

    original_log2_series = df['log2'].copy()
    cnr_original_mean = np.nan
    cnr_original_std = np.nan

    if not original_log2_series.empty:
        if len(original_log2_series.unique()) == 1:
            cnr_original_mean = original_log2_series.iloc[0]
            cnr_original_std = 0.0
            df.loc[:, 'log2'] = 0.0
        else:
            cnr_original_mean = original_log2_series.mean()
            cnr_original_std = original_log2_series.std()
            # Restore biological log2 units by only centering, NOT dividing by SD
            if cnr_original_std is not None and cnr_original_std > 1e-9:
                df.loc[:, 'log2'] = (original_log2_series - cnr_original_mean)
            else:
                df.loc[:, 'log2'] = 0.0
                if cnr_original_std is None or cnr_original_std <= 1e-9:
                    cnr_original_std = 0.0
    return df, cnr_original_mean, cnr_original_std


def calculate_purified_log2(log2_obs, purity):
    """
    Adjusts the observed log2 ratio for a given tumor purity.
    Formula: Ratio_Obs = Purity * Ratio_Pure + (1-Purity)
             Ratio_Pure = (Ratio_Obs - (1-Purity)) / Purity
    """
    if purity >= 1.0:
        return log2_obs

    try:
        ratio_obs = 2.0 ** log2_obs
        term = (ratio_obs - (1.0 - purity)) / purity

        # Safety clip of the ratio before log2 to a very small epsilon (1e-6)
        # log2(1e-6) is ~ -19.9, providing a much lower floor.
        if isinstance(term, pd.Series):
            term = term.clip(lower=1e-6)
        else:
            term = max(term, 1e-6)

        return np.log2(term)
    except Exception as e:
        print(f"Warning: Error in purity adjustment: {e}. Returning original log2.", file=sys.stderr)
        return log2_obs


def load_cns_file(cns_filepath: Path, chromosome_start_map: dict,
                  cnr_original_mean: float, cnr_original_std: float):
    """
    Loads and preprocesses a .call.cns file, normalizes its log2 values.
    Ensures chromosome column is string type. chromosome_start_map keys are strings.
    """
    if not cns_filepath.exists():
        print(f"Warning: CNS file not found at {cns_filepath}. Segment means will not be plotted.", file=sys.stderr)
        return pd.DataFrame()

    try:
        df = pd.read_csv(cns_filepath, sep='\t')
        # Ensure chromosome column is string type right after loading
        if 'chromosome' in df.columns:
            df.loc[:, 'chromosome'] = df['chromosome'].astype(str)
        else:
            print(f"Error: 'chromosome' column not found in {cns_filepath.name}", file=sys.stderr)
            return pd.DataFrame()
    except Exception as e:
        print(f"Error reading CNS file {cns_filepath}: {e}", file=sys.stderr)
        return pd.DataFrame()

    required_cols = ['chromosome', 'start', 'end', 'log2']  # chromosome already checked basically
    if not all(col in df.columns for col in required_cols if col != 'chromosome'):  # Check remaining
        missing = [col for col in required_cols if col not in df.columns]
        if missing:  # Only print if there are actually missing required cols other than 'chromosome' if it failed above
            print(f"Error: CNS file {cns_filepath} is missing required columns: {missing}", file=sys.stderr)
            return pd.DataFrame()

    if df.empty:
        print(f"Warning: No data in {cns_filepath.name} after initial load.", file=sys.stderr)
        return pd.DataFrame()

    for col in ['start', 'end']:
        df[col] = pd.to_numeric(df[col], errors='coerce').astype(pd.Int64Dtype())
    df.loc[:, 'log2'] = pd.to_numeric(df['log2'], errors='coerce')

    df = df.dropna(subset=['chromosome', 'start', 'end', 'log2'])
    if df.empty:
        print(f"Warning: No valid data in {cns_filepath.name} after dropping NaNs in key CNS columns.", file=sys.stderr)
        return pd.DataFrame()

    if pd.notna(cnr_original_mean) and pd.notna(cnr_original_std):
        # Restore biological log2 units by only centering
        df['log2'] = (df['log2'] - cnr_original_mean)
    else:
        print(f"Warning: CNS log2 values for {cns_filepath.name} cannot be normalized... Setting CNS log2 to NaN.",
              file=sys.stderr)
        df['log2'] = np.nan

    df.loc[:, 'chromosome_absolute_start'] = df['chromosome'].map(chromosome_start_map)

    if df['chromosome_absolute_start'].isna().any():
        print(f"Warning: Some segments in {cns_filepath.name} are on chromosomes not found in cytoband data...dropped.",
              file=sys.stderr)
        df = df.dropna(subset=['chromosome_absolute_start'])

    if df.empty:
        print(f"Warning: No segments remaining in {cns_filepath.name} after mapping or invalid log2.", file=sys.stderr)
        return pd.DataFrame()

    df.loc[:, 'cns_segment_absolute_start'] = df['chromosome_absolute_start'] + df['start']
    df.loc[:, 'cns_segment_absolute_end'] = df['chromosome_absolute_start'] + df['end']

    return df


def annotate_segments_with_genes(df, gene_interval_trees, genes_df, padding=GENE_ANNOTATION_PADDING):
    """Annotates DataFrame segments with overlapping genes."""
    if df.empty:
        if 'gene' not in df.columns:
            df['gene'] = pd.NA
        return df

    all_relevant_genes = set(genes_df['gene'])
    df.loc[:, 'chromosome'] = df['chromosome'].astype(str)

    # Identify valid "panel genes" already in the dataframe. These will be excluded from the search.
    is_not_na = df['gene'].notna()
    is_valid = df['gene'].isin(all_relevant_genes)
    genes_on_panel = set(df.loc[is_not_na & is_valid, 'gene'])

    # Invalidate any existing gene annotations that are not in our master list of relevant genes.
    df.loc[is_not_na & ~is_valid, 'gene'] = pd.NA

    # Iterate only over rows that need a gene (originally NA or invalidated).
    rows_to_annotate = df['gene'].isna()
    for index, row in df[rows_to_annotate].iterrows():
        tree = gene_interval_trees.get(row.chromosome)
        if not tree:
            continue

        overlaps = tree.overlap(max(0, row.start - padding), row.end + padding)
        if overlaps:
            # Filter overlaps to only include genes that are NOT already on the panel.
            additional_gene_overlaps = {
                iv for iv in overlaps if iv.data['gene'] not in genes_on_panel
            }

            if additional_gene_overlaps:
                # If any such "additional" genes are found, pick the first one and annotate.
                first_overlap = sorted(additional_gene_overlaps, key=lambda i: (i.begin, i.data['gene']))[0]
                df.at[index, 'gene'] = first_overlap.data['gene']

    return df


def prep_ngs_for_plotting(df, chrom_start_map):
    """Calculates absolute start position. df['chromosome'] is string. chrom_start_map keys are strings."""
    if df.empty or not chrom_start_map:
        print("Warning: Cannot prepare NGS data for plotting without data or chromosome map.", file=sys.stderr)
        return df.assign(absolute_start=np.nan, length=np.nan)  # ensure columns exist

    # Ensure chromosome column is string for mapping
    df.loc[:, 'chromosome'] = df['chromosome'].astype(str)

    valid_chroms = df['chromosome'].isin(chrom_start_map.keys())
    if not valid_chroms.all():
        print(f"Warning: {sum(~valid_chroms)} bins have chromosomes not found in chromosome map...", file=sys.stderr)

    df.loc[:, 'absolute_start'] = df['chromosome'].map(chrom_start_map) + ((df['start'] + df['end']) // 2)
    df.loc[:, 'length'] = df['end'] - df['start']
    return df


def aggregate_data_by_gene(annotated_df, plot_y_lim, merge_distance=GENE_MERGE_DISTANCE):
    """Aggregates log2 data to gene level based on annotation."""
    if (annotated_df.empty or
            'gene' not in annotated_df.columns or
            'absolute_start' not in annotated_df.columns or
            'log2' not in annotated_df.columns):
        print("Warning: Cannot aggregate by gene due to missing data or columns (gene, absolute_start, log2).",
              file=sys.stderr)
        return pd.DataFrame()

    ngs_with_gene = annotated_df[annotated_df['gene'].notna() & annotated_df['log2'].notna()].copy()
    if ngs_with_gene.empty:
        return pd.DataFrame()

    gene_reps = ngs_with_gene.groupby(['gene', 'case_identifier']).agg(
        absolute_position=('absolute_start', 'median'),
        log2=('log2', 'median')
    ).reset_index()

    if gene_reps.empty:
        return gene_reps

    # Merge labels of genes that are now close together based on their median positions.
    gene_reps = gene_reps.sort_values('absolute_position').reset_index(drop=True)

    if merge_distance <= 0:  # If no merging is desired, just clip and return
        gene_reps.loc[:, 'log2'] = gene_reps['log2'].clip(lower=-plot_y_lim, upper=plot_y_lim)
        return gene_reps

    groups = []
    current_group = []
    for _, row in gene_reps.iterrows():
        if not current_group:
            current_group.append(row)
            continue

        last_row_in_group = current_group[-1]
        # Check distance between the median positions of the two genes
        if (row.absolute_position - last_row_in_group.absolute_position) > merge_distance:
            groups.append(current_group)
            current_group = [row]
        else:
            current_group.append(row)

    if current_group:
        groups.append(current_group)

    # Re-aggregate the grouped genes
    final_reps_data = []
    for group in groups:
        if len(group) == 1:
            final_reps_data.append(group[0].to_dict())
        else:
            group_df = pd.DataFrame(group)
            unique_genes = sorted(list(set(group_df['gene'])))
            merged_name = _merge_gene_names(unique_genes)

            merged_row = {
                'gene': merged_name,
                'case_identifier': group_df['case_identifier'].iloc[0],
                'absolute_position': group_df['absolute_position'].median(),
                'log2': group_df['log2'].loc[group_df['log2'].abs().idxmax()]
            }
            final_reps_data.append(merged_row)

    if not final_reps_data:
        return pd.DataFrame()

    merged_gene_reps = pd.DataFrame(final_reps_data)
    merged_gene_reps.loc[:, 'log2'] = merged_gene_reps['log2'].clip(lower=-plot_y_lim, upper=plot_y_lim)

    return merged_gene_reps


def _merge_gene_names(gene_list):
    """
    Merges a list of gene names intelligently.
    e.g., ['CDKN2A', 'CDKN2B'] becomes 'CDKN2A/B'.
    """
    if len(gene_list) <= 1:
        return '/'.join(gene_list)

    # Find the longest common starting string
    prefix = path.commonprefix(gene_list)

    # If the prefix is trivial, don't shorten, just join
    if len(prefix) < 3:
        return '/'.join(gene_list)

    # Keep the first gene name whole, append only suffixes of the rest
    suffixes = [gene[len(prefix):] for gene in gene_list[1:]]
    return '/'.join([gene_list[0]] + suffixes)

# --- Plotting Functions ---

def _plot_ngs_scatter(ax, ngs_df_case, plot_y_lim):
    """Plots individual NGS bins. Colors based on log2 value (gain/loss/neutral)."""
    if ngs_df_case.empty or 'log2' not in ngs_df_case.columns or 'absolute_start' not in ngs_df_case.columns:
        return

    log2_values = pd.to_numeric(ngs_df_case['log2'], errors='coerce').clip(-plot_y_lim, plot_y_lim)
    abs_pos = ngs_df_case['absolute_start']

    # Calculate alpha based on z-score of log2 values
    if len(log2_values) > 1:  # zscore needs at least 2 points
        # zscore returns a numpy array if input is a Series, re-index to match original
        abs_z = np.abs(zscore(log2_values.to_numpy()))
        calculated_alphas = np.clip((abs_z / 3) ** 2.25, 0.01, 1.0)
        alphas = pd.Series(calculated_alphas, index=log2_values.index)
    else:
        alphas = pd.Series([0.5], index=log2_values.index)  # Default alpha for a single point

    # Define colors
    color_gain = 'firebrick'
    color_loss = 'tab:blue'
    color_neutral = 'grey'

    # Create masks for plotting, excluding NaNs from these categories
    mask_gain = (log2_values > 1e-6)  # Use a small epsilon for > 0
    mask_loss = (log2_values < -1e-6)  # Use a small epsilon for < 0
    mask_neutral = np.isclose(log2_values, 0, atol=1e-6)

    # Plot gains
    if mask_gain.any():
        ax.scatter(abs_pos[mask_gain], log2_values[mask_gain],
                   color=color_gain, alpha=alphas[mask_gain], s=1.2, label='NGS gain (log2 > 0)')

    # Plot losses
    if mask_loss.any():
        ax.scatter(abs_pos[mask_loss], log2_values[mask_loss],
                   color=color_loss, alpha=alphas[mask_loss], s=1.2, label='NGS loss (log2 < 0)')

    # Plot neutral points
    if mask_neutral.any():
        ax.scatter(abs_pos[mask_neutral], log2_values[mask_neutral],
                   color=color_neutral, alpha=alphas[mask_neutral], s=1.2, label='NGS neutral (log2 ≈ 0)')

    # Note: log2_values that are NaN will not be plotted by the above masks.


def _plot_cns_segments(ax, df_cns_segments, color, linestyle, linewidth, label_text, plot_y_lim):
    """Plots CNS segments from .call.cns file as horizontal lines."""
    if df_cns_segments.empty or not all(
            c in df_cns_segments.columns for c in ['cns_segment_absolute_start', 'cns_segment_absolute_end', 'log2']):
        if not df_cns_segments.empty:
            print(
                f"Warning: CNS segments DataFrame is missing required columns for plotting. Present: {df_cns_segments.columns.tolist()}",
                file=sys.stderr)
        return

    for idx, row in df_cns_segments.iterrows():
        if pd.notna(row['log2']) and \
                pd.notna(row['cns_segment_absolute_start']) and \
                pd.notna(row['cns_segment_absolute_end']):
            plot_log2_val = np.clip(row['log2'], -plot_y_lim, plot_y_lim)
            ax.plot(
                [row['cns_segment_absolute_start'], row['cns_segment_absolute_end']],
                [plot_log2_val, plot_log2_val],
                color=color,
                linestyle=linestyle,
                linewidth=linewidth,
                label=label_text if idx == 0 else None
            )


def _plot_gene_labels(ax, gene_reps_case, plot_y_lim):
    """Plots gene annotations as points and text labels."""
    if gene_reps_case.empty or not all(c in gene_reps_case.columns for c in ['absolute_position', 'log2', 'gene']):
        return

    valid_gene_reps = gene_reps_case.dropna(subset=['absolute_position', 'log2', 'gene'])
    if valid_gene_reps.empty: return

    ax.scatter(
        valid_gene_reps['absolute_position'],
        valid_gene_reps['log2'],
        color='black', s=4, label='genes'
    )

    for _, row in valid_gene_reps.iterrows():
        x = row['absolute_position']
        y, name = row['log2'], row['gene']

        # place label on top for positive y, below for negative y
        offset = 0.02 * plot_y_lim if y > 0 else -0.02 * plot_y_lim
        if abs(y) > plot_y_lim * 0.75: # invert if text would be too close to the plot limit
            offset = -1 * offset
        va = 'bottom' if offset > 0 else 'top'
        ax.text(x, y + offset, name, fontsize=9, ha='center', va=va, rotation=90)


def draw_cnv_plot(case_identifier, df_ngs_case, df_cns_segments, df_gene_reps,
                  df_chroms, arm_boundaries, output_dir, output_filename, plot_y_lim):
    """Generates and saves the CNV plot for a single case."""
    fig, ax = plt.subplots(figsize=(11, 6))

    _plot_ngs_scatter(ax, df_ngs_case, plot_y_lim)
    _plot_cns_segments(ax, df_cns_segments, 'darkviolet', '-', 1.5, 'called segment copy number', plot_y_lim)
    _plot_gene_labels(ax, df_gene_reps, plot_y_lim)

    ax.axhline(0, color='grey', linewidth=0.5)
    xlim_max = None
    if not df_chroms.empty and all(
            c in df_chroms.columns for c in ['chromosome_absolute_start', 'length', 'chromosome']):
        chrom_starts = df_chroms['chromosome_absolute_start']
        ax.vlines(chrom_starts, -plot_y_lim, plot_y_lim, color='grey', linestyle='--', linewidth=0.5)

        # Plot p/q arm boundaries
        if arm_boundaries:
            ax.vlines(arm_boundaries, -plot_y_lim, plot_y_lim, color='grey', linestyle=':', linewidth=0.3)

        mids = chrom_starts + df_chroms['length'] / 2
        ax.set_xticks(mids)
        ax.set_xticklabels(df_chroms['chromosome'], rotation=90)
        xlim_max = df_chroms['chromosome_absolute_start'].iloc[-1] + df_chroms['length'].iloc[-1]

    if xlim_max is None:
        all_abs_positions = []
        if not df_ngs_case.empty and 'absolute_start' in df_ngs_case.columns and df_ngs_case[
            'absolute_start'].notna().any():
            all_abs_positions.extend(df_ngs_case['absolute_start'].dropna().tolist())
        if not df_cns_segments.empty and 'cns_segment_absolute_end' in df_cns_segments.columns and df_cns_segments[
            'cns_segment_absolute_end'].notna().any():
            all_abs_positions.extend(df_cns_segments['cns_segment_absolute_end'].dropna().tolist())
        if not df_gene_reps.empty and 'absolute_position' in df_gene_reps.columns and df_gene_reps[
            'absolute_position'].notna().any():
            all_abs_positions.extend(df_gene_reps['absolute_position'].dropna().tolist())
        xlim_max = max(all_abs_positions) * 1.05 if all_abs_positions else 1

    ax.set(
        xlim=(0, xlim_max if xlim_max > 0 else 1),
        ylim=(-plot_y_lim, plot_y_lim),
        xlabel='genomic position by chromosome',
        ylabel='copy number deviation (log2)'
    )

    plt.suptitle(f'CNV profile for {case_identifier}', fontsize=14, y=0.92)
    ax.grid(False)
    ax.legend().set_visible(False)

    plt.tight_layout(rect=[0, 0, 1, 0.95])

    output_dir.mkdir(parents=True, exist_ok=True)
    fname = output_dir / (output_filename if output_filename else f"cnv_plot_{case_identifier.replace('/', '_')}.png")
    try:
        plt.savefig(fname, dpi=150, bbox_inches='tight')
        print(f"Saved plot: {fname}")
    except Exception as e:
        print(f"Error saving plot {fname}: {e}", file=sys.stderr)
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(
        description="Generate a CNV plot from an NGS .cnr file and its .call.cns file.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    parser.add_argument("cnr_file", type=Path, help="Path to the input .cnr file.")
    parser.add_argument("-c", "--cytoband", type=Path, default=DEFAULT_CYTOBAND_PATH, help="Path to cytoband file.")
    parser.add_argument("-g", "--genes", type=Path, default=DEFAULT_RELEVANT_GENES_PATH,
                        help="Path to relevant genes CSV.")
    parser.add_argument("-o", "--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR, help="Output directory for plot.")
    parser.add_argument("-f", "--output-filename", type=Path, default=None, help="Output plot filename.")
    parser.add_argument("--case-id", type=str, default=None, help="Optional case identifier.")
    parser.add_argument("--gene_annotation_padding", type=int, default=GENE_ANNOTATION_PADDING,
                        help="Padding for gene annotation.")
    parser.add_argument("--purity", type=float, default=1.0, help="Tumor purity (0.1 to 1.0).")
    args = parser.parse_args()

    print("Loading static data...")
    cytoband_df = load_and_preprocess_cytoband(args.cytoband)
    genes_df = load_and_preprocess_relevant_genes(args.genes)

    print("Preprocessing static data...")
    chroms_df, chrom_map, arm_boundaries = calculate_chromosome_features(cytoband_df)
    # arm_map_df and arm_lookup_table creation removed
    gene_trees = build_gene_interval_trees(genes_df)

    if chroms_df.empty or not chrom_map:
        print("Error: Failed to process cytoband features. Exiting.", file=sys.stderr)
        sys.exit(1)

    case_identifier = args.case_id if args.case_id else extract_case_identifier(args.cnr_file)
    print(f"Processing .cnr file for case: {case_identifier}...")
    ngs_raw_df, cnr_original_mean, cnr_original_std = load_ngs_cnr_file(args.cnr_file, case_identifier)

    if ngs_raw_df is None or ngs_raw_df.empty:
        print(f"Error: Failed to load/process {args.cnr_file}. Exiting.", file=sys.stderr)
        sys.exit(1)

    cns_filepath = args.cnr_file.with_suffix('.call.cns')
    print(f"Loading CNS segment data from: {cns_filepath}...")
    cns_segments_df = load_cns_file(cns_filepath, chrom_map, cnr_original_mean, cnr_original_std)

    if args.purity < 1.0:
        print(f"Applying tumor purity adjustment (Purity: {args.purity})...")
        ngs_raw_df.loc[:, 'log2'] = calculate_purified_log2(ngs_raw_df['log2'], args.purity)
        if not cns_segments_df.empty:
            cns_segments_df.loc[:, 'log2'] = calculate_purified_log2(cns_segments_df['log2'], args.purity)

    print("Preparing NGS data for plotting...")
    ngs_processed_df = prep_ngs_for_plotting(ngs_raw_df.copy(), chrom_map)

    # Calculate dynamic PLOT_Y_LIM based on a high percentile.
    # We use the 99th percentile to capture 99% of the signal while trimming 
    # extreme single-probe noise or rare artifacts that would squash the y-axis.
    abs_log2 = ngs_processed_df['log2'].abs().dropna()
    if not abs_log2.empty:
        # 99th percentile provides a "robust maximum". 
        # We add 10% headroom (1.1x) to ensure peaks aren't touching the edge.
        dynamic_limit = abs_log2.quantile(0.99) * 1.1
        
        # Ensure we don't go below the default minimum, and cap at a reasonable max.
        plot_y_lim = max(DEFAULT_PLOT_Y_LIM, dynamic_limit)
        plot_y_lim = min(plot_y_lim, 25.0)
    else:
        plot_y_lim = DEFAULT_PLOT_Y_LIM
    
    print(f"Dynamic Plot Y Limit: {plot_y_lim:.2f}")

    ngs_processed_df = annotate_segments_with_genes(ngs_processed_df, gene_trees, genes_df, args.gene_annotation_padding)
    ngs_gene_reps = aggregate_data_by_gene(ngs_processed_df, plot_y_lim)

    print(f"NGS Bins: {len(ngs_processed_df)}")
    print(f"CNS Segments: {len(cns_segments_df)}")
    print(f"Gene Representatives: {len(ngs_gene_reps)}")

    print(f"Generating CNV plot for {case_identifier}...")
    draw_cnv_plot(
        case_identifier, ngs_processed_df, cns_segments_df, ngs_gene_reps,
        chroms_df, arm_boundaries, args.output_dir, args.output_filename, plot_y_lim
    )
    print("Done.")


if __name__ == "__main__":
    main()