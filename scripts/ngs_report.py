#!/usr/bin/env python3

import argparse
import os
import glob
import pandas as pd
import re
import json
from datetime import datetime
from xml.sax.saxutils import escape

from reportlab.platypus import (Paragraph, Spacer, Image, Table,
                                TableStyle, BaseDocTemplate, Frame, PageTemplate,
                                HRFlowable, KeepTogether)
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.lib import colors, utils
from reportlab.lib.pagesizes import A4

# --- Constants and Configuration ---
HIGHLIGHT_GENES = [
    "ALK", "BRAF", "CD74", "EGFR", "EWSR1", "FGFR1", "FGFR2", "FGFR3",
    "MET", "NTRK1", "NTRK2", "NTRK3", "ETV6", "RET", "RELA", "ROS1"
]
BLACK = colors.black
WHITE = colors.white
LIGHT_GREY = colors.HexColor("#F7F7F7")

# Spacing constants for consistent report layout
SECTION_SPACING = 0.3 * inch
SUB_SECTION_SPACING = 0.2 * inch
TABLE_WIDTH_FACTOR = 0.96 # Factor to make tables slightly narrower than full width

CNV_REFERENCE_FILE = "panel_v4.1"
CNV_REFERENCE_DATE = "08.08.2025"

# --- Page Setup ---
def header_footer(canvas, doc):
    canvas.saveState()
    canvas.setFont('Helvetica-Bold', 7)
    canvas.setFillColor(BLACK)
    
    y_pos = doc.height + doc.topMargin - 0.4 * inch
    
    if getattr(doc, 'is_metagenomics_sample', False):
        part1 = "NGS Report - "
        part2 = "Metagenomics"
        
        canvas.setFillColor(BLACK)
        canvas.drawString(doc.leftMargin, y_pos, part1)
        
        # Calculate the width to position the second part
        width1 = canvas.stringWidth(part1, 'Helvetica-Bold', 7)
        x_pos_part2 = doc.leftMargin + width1
        
        canvas.setFillColor(colors.red)
        canvas.drawString(x_pos_part2, y_pos, part2)

    else:
        canvas.drawString(doc.leftMargin, y_pos, "NGS Report")
    
    canvas.setFillColor(BLACK)
    canvas.drawRightString(
        doc.width + doc.leftMargin,
        doc.height + doc.topMargin - 0.4 * inch,
        datetime.now().strftime("%d.%m.%Y")
    )
    file_prefix = getattr(doc, 'file_prefix', '')
    if file_prefix:
        canvas.drawString(doc.leftMargin, 0.4 * inch, f"Sample: {file_prefix}")
    page_num_text = f"Page {canvas.getPageNumber()}"
    canvas.drawRightString(doc.width + doc.leftMargin, 0.4 * inch, page_num_text)
    canvas.restoreState()

def create_pdf_document(output_path):
    doc = BaseDocTemplate(
        output_path, pagesize=A4,
        leftMargin=1 * inch, rightMargin=1 * inch,
        topMargin=1 * inch, bottomMargin=0.5 * inch
    )
    frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id='normal')
    template = PageTemplate(id='main', frames=[frame], onPage=header_footer)
    doc.addPageTemplates([template])
    return doc

# --- Helper Functions ---
def get_file_path(directory, pattern):
    """Finds the first file matching a pattern in a directory."""
    if not os.path.isdir(directory):
        print(f"Warning: Directory not found: '{directory}'")
        return None
    files = glob.glob(os.path.join(directory, pattern))
    if not files:
        print(f"Warning: No file for pattern '{pattern}' in '{directory}'")
        return None
    return files[0]

def create_section_header(text, styles):
    """Creates a styled section header with a horizontal line."""
    p = Paragraph(text, styles['SectionHeader'])
    line = HRFlowable(width="100%", thickness=1, color=BLACK, spaceAfter=8)
    line.keepWithNext = True
    return [p, line]

def highlight_gene_text(text, gene_list=None, color="red"):
    """Returns escaped text for ReportLab Paragraphs with optional highlighting."""
    if not isinstance(text, str): return text
    escaped_text = escape(text)
    if gene_list and text in gene_list:
        return f'<font color="{color}"><b>{escaped_text}</b></font>'
    return escaped_text

def create_styled_table(df, styles, table_style, col_widths=None, hAlign='LEFT'):
    """Creates a styled ReportLab Table from a pandas DataFrame, applying a given style."""
    header = [Paragraph(f'<b>{col}</b>', styles['TableCell']) for col in df.columns]
    
    data_rows = []
    for _, row in df.iterrows():
        data_row = [item if isinstance(item, Paragraph) else Paragraph(str(item), styles['TableCell']) for item in row]
        data_rows.append(data_row)
        
    table = Table([header] + data_rows, colWidths=col_widths, hAlign=hAlign, repeatRows=1)
    # Add light grey background to the header row
    table_style.add('BACKGROUND', (0, 0), (-1, 0), colors.HexColor("#EEEEEE"))
    table.setStyle(table_style)
    return table

def get_proportional_image(path, desired_width):
    """Loads an image and scales it proportionally."""
    try:
        reader = utils.ImageReader(path)
        iw, ih = reader.getSize()
        aspect = ih / float(iw) if iw else 0
        return Image(path, width=desired_width, height=(desired_width * aspect))
    except Exception as e:
        print(f"Warning: Could not load image '{path}': {e}")
        return None

      
def extract_qc_value(html_content, key):
    """Extracts a value from a simple two-column HTML table."""
    pattern = re.compile(rf"<tr>\s*<td class='col1'>{re.escape(key)}</td>\s*<td class='col2'>(.*?)</td>\s*</tr>", re.DOTALL)
    match = pattern.search(html_content)
    return match.group(1).strip() if match else "Not Found"

def filter_kraken_results(df, threshold=3):
    if 'reads' not in df.columns:
        return df, 0

    initial_count = len(df)
    # Keep rows where the number of reads is greater than or equal to the threshold
    filtered_df = df[df['reads'] >= threshold].copy()
    final_count = len(filtered_df)
    
    removed_count = initial_count - final_count
    return filtered_df, removed_count

# --- Section Generation Functions ---
def generate_qc_section(directory, doc_width, styles):
    section_content = create_section_header("Quality control", styles)
    
    fastp_dir = os.path.join(directory, 'fastp')
    qc_html_path = get_file_path(fastp_dir, "*fastp.html") or get_file_path(fastp_dir, "*.html")

    if not qc_html_path:
        section_content.append(Paragraph("Quality control report (fastp.html) not found.", styles['Normal']))
    else:
        try:
            with open(qc_html_path, 'r', encoding='utf-8') as f:
                html_content = f.read()
            
            keys_col1 = { "sequencing:": "Sequencing", "mean length before filtering:": "Mean length before filtering", "mean length after filtering:": "Mean length after filtering", "duplication rate:": "Duplication rate", "Insert size peak:": "Insert size peak" }
            keys_col2 = { "total reads:": "Total reads", "total bases:": "Total bases", "Q20 bases:": "Q20 bases", "Q30 bases:": "Q30 bases", "GC content:": "GC content" }
            before_filtering_match = re.search(r"<div id='before_filtering_summary'>(.*?)</div>", html_content, re.DOTALL)
            before_filtering_content = before_filtering_match.group(1) if before_filtering_match else ""
            
            table_data = []
            key_list1, key_list2 = list(keys_col1.items()), list(keys_col2.items())
            for i in range(max(len(key_list1), len(key_list2))):
                row = []
                if i < len(key_list1):
                    key, label = key_list1[i]
                    val = extract_qc_value(html_content, key)
                    row.extend([Paragraph(f"<b>{label}:</b>", styles['TableCell']), Paragraph(escape(val), styles['TableCell'])])
                else: row.extend(["", ""])
                if i < len(key_list2):
                    key, label = key_list2[i]
                    val = extract_qc_value(before_filtering_content, key)
                    row.extend([Paragraph(f"<b>{label}:</b>", styles['TableCell']), Paragraph(escape(val), styles['TableCell'])])
                else: row.extend(["", ""])
                table_data.append(row)

            label_width = 1.4 * inch; value_width = (doc_width / 2) - label_width
            qc_table = Table(table_data, colWidths=[label_width, value_width, label_width, value_width], hAlign='LEFT')
            qc_table.setStyle(TableStyle([('VALIGN', (0, 0), (-1, -1), 'TOP'), ('LEFTPADDING', (0, 0), (-1, -1), 0), ('RIGHTPADDING', (0, 0), (-1, -1), 5)]))
            section_content.append(qc_table)
        except Exception as e:
            section_content.append(Paragraph(f"Could not read QC report: {e}", styles['Normal']))

    section_content.append(Spacer(1, 0.1 * inch))
    cnv_dir = os.path.join(directory, 'cnv')
    # Check for sex prediction in cnv/
    sex_file = get_file_path(cnv_dir, "*_sex.txt")
    if sex_file:
        try:
            df_sex = pd.read_csv(sex_file, sep='\t')
            predicted_sex = df_sex['sex'].mode()[0] if 'sex' in df_sex.columns else "Unknown"
            section_content.append(Paragraph(f"<b>Predicted sex:</b> {predicted_sex}", styles['TableCell']))
        except Exception as e:
            section_content.append(Paragraph(f"Could not read sex prediction: {e}", styles['Normal']))
    else:
        section_content.append(Paragraph("<b>Predicted sex:</b> not determined", styles['Normal']))

    if section_content:
        section_content[-1].spaceAfter = SECTION_SPACING

    return section_content


def generate_cnv_section(directory, doc_width, styles, is_metagenomics=False):
    story = create_section_header("Copy number profile", styles)
    story.append(Paragraph(f"Reference: {CNV_REFERENCE_FILE} ({CNV_REFERENCE_DATE})", styles['Normal']))
    cnvdir = os.path.join(directory, 'cnv')

    # 1. Panel Coverage (Moved to top of section per user request)
    if not is_metagenomics:
        coverage_dir = os.path.join(cnvdir, 'coverage')
        cov = get_file_path(coverage_dir, "*_panel_coverage.png")
        if cov and (ci := get_proportional_image(cov, doc_width * TABLE_WIDTH_FACTOR)):
            ci.hAlign = 'CENTER'
            # Removed explicit Spacer to reduce gap after reference line
            story.append(KeepTogether([Paragraph("Panel coverage", styles['SubHeader']), ci]))

    # 2. Whole-genome CNV
    plot = get_file_path(cnvdir, "cnv_plot.png")
    if plot and (img := get_proportional_image(plot, doc_width * TABLE_WIDTH_FACTOR)):
        story.append(Spacer(1, SUB_SECTION_SPACING))
        story.append(KeepTogether([Paragraph("Genome-wide copy number profile", styles['SubHeader']), img]))
    else:
        story.append(Paragraph("Global CNV plot not found.", styles['Normal']))

    if story:
        story[-1].spaceAfter = SECTION_SPACING
    return story

def generate_focal_cnv_section(directory, doc_width, styles):
    story = []
    cnvdir = os.path.join(directory, 'cnv')
    
    def chrom_sort_key(path):
        """Extracts chromosome number/name for genomic sorting."""
        m = re.search(r'_chr(\d+|X|Y)\.png$', path)
        if not m: return 999
        c = m.group(1)
        if c == 'X': return 23
        if c == 'Y': return 24
        return int(c)

    focal_plots = sorted(glob.glob(os.path.join(cnvdir, "*_chr*.png")), key=chrom_sort_key)
    if focal_plots:
        story.append(Paragraph("Focal copy number profiles", styles['SubHeader'])) 
        table_data = []
        row = []
        # Arrange images 3 per row to save space
        for p in focal_plots:
            img = get_proportional_image(p, doc_width * 0.32)
            if img:
                row.append(img)
            if len(row) == 3:
                table_data.append(row)
                row = []
        if row:
            # Pad the last row with empty strings
            while len(row) < 3:
                row.append("")
            table_data.append(row)
            
        if table_data:
            focal_table = Table(table_data, colWidths=[doc_width / 3.0] * 3, style=[('VALIGN', (0, 0), (-1, -1), 'TOP')])
            story.append(focal_table) 

    if story:
        story[-1].spaceAfter = SECTION_SPACING
    return story

def generate_fusions_section(directory, doc_width, styles, fusion_genes=None):
    story = create_section_header("Gene fusions", styles)
    fusion_file = get_file_path(os.path.join(directory, 'arriba'), "*fusions.tsv")

    if not fusion_file:
        story.append(Paragraph("Fusion data file not found.", styles['Normal']))
    else:
        try:
            df = pd.read_csv(fusion_file, sep='\t')
            if df.empty:
                story.append(Paragraph("No fusions detected.", styles['Normal']))
            else:
                # Reorder columns for logical pairing: [Gene1, Split1, Gene2, Split2, Disc, Conf]
                df = df[['#gene1', 'split_reads1', 'gene2', 'split_reads2', 'discordant_mates', 'confidence']].copy()
                
                # Prepare table data with a two-row grouped header
                # Row 0: Group labels
                header_row0 = [
                    Paragraph("<b>Gene 1</b>", styles['TableCell']), "",
                    Paragraph("<b>Gene 2</b>", styles['TableCell']), "",
                    "", ""
                ]
                # Row 1: Specific labels
                header_row1 = [
                    Paragraph("<b>Name</b>", styles['TableCell']),
                    Paragraph("<b>Split reads</b>", styles['TableCell']),
                    Paragraph("<b>Name</b>", styles['TableCell']),
                    Paragraph("<b>Split reads</b>", styles['TableCell']),
                    Paragraph("<b>Discordant reads</b>", styles['TableCell']),
                    Paragraph("<b>Confidence</b>", styles['TableCell'])
                ]
                
                table_data = [header_row0, header_row1]
                
                for _, row in df.iterrows():
                    table_data.append([
                        Paragraph(highlight_gene_text(str(row['#gene1']), fusion_genes), styles['TableCell']),
                        Paragraph(str(row['split_reads1']), styles['TableCell']),
                        Paragraph(highlight_gene_text(str(row['gene2']), fusion_genes), styles['TableCell']),
                        Paragraph(str(row['split_reads2']), styles['TableCell']),
                        Paragraph(str(row['discordant_mates']), styles['TableCell']),
                        Paragraph(str(row['confidence']), styles['TableCell'])
                    ])
                
                # Proportions: Gene Section 1 (35%), Gene Section 2 (35%), Support (30%)
                target_width = doc_width * TABLE_WIDTH_FACTOR
                proportions = [0.25, 0.1, 0.25, 0.1, 0.15, 0.15]
                col_widths = [p * target_width for p in proportions]
                
                fusions_table_style = TableStyle([
                    ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
                    ('INNERGRID', (0, 0), (-1, -1), 0.25, BLACK),
                    ('BOX', (0, 0), (-1, -1), 0.5, BLACK),
                    ('ROWBACKGROUNDS', (0, 2), (-1, -1), [WHITE, LIGHT_GREY]),
                    ('ALIGN', (1, 0), (1, -1), 'CENTER'), # Center Split 1
                    ('ALIGN', (3, 0), (5, -1), 'CENTER'), # Center Split 2, Disc, Conf
                    
                    # Header backgrounds
                    ('BACKGROUND', (0, 0), (-1, 1), colors.HexColor("#EEEEEE")),
                    
                    # Spanning Grouped Headers
                    ('SPAN', (0, 0), (1, 0)), # Gene 1 Group
                    ('ALIGN', (0, 0), (1, 0), 'CENTER'),
                    ('SPAN', (2, 0), (3, 0)), # Gene 2 Group
                    ('ALIGN', (2, 0), (3, 0), 'CENTER'),
                    ('SPAN', (4, 0), (5, 0)), # Support Group
                    ('ALIGN', (4, 0), (5, 0), 'CENTER'),
                ])
                
                table = Table(table_data, colWidths=col_widths, hAlign='CENTER', repeatRows=2)
                table.setStyle(fusions_table_style)
                story.append(table)
                
        except Exception as e:
            story.append(Paragraph(f"Could not process fusion file: {e}", styles['Normal']))

    if story:
        story[-1].spaceAfter = SECTION_SPACING
    return story


def create_variant_table(variants, styles, doc_width, is_qc=False):
    """Helper to create a variant table for either Main or QC variants."""
    if not variants:
        return None

    if is_qc:
        # QC variants: Remove Interpretation column
        headers = ["Gene", "Mutation status", "VAF", "Depth"]
        proportions = [0.15, 0.65, 0.1, 0.1]
        vaf_col_idx = 2
    else:
        # Main variants: Keep Interpretation column
        headers = ["Gene", "Mutation status", "Interpretation", "VAF", "Depth"]
        proportions = [0.15, 0.45, 0.2, 0.1, 0.1]
        vaf_col_idx = 3

    table_data = [[Paragraph(f"<b>{h}</b>", styles['TableCell']) for h in headers]]

    for v in variants:
        if is_qc:
            table_data.append([
                Paragraph(highlight_gene_text(v.get("gene", "")), styles['TableCell']),
                Paragraph(v.get("hgvs", ""), styles['TableCell']),
                Paragraph(f"{v.get('vaf', 0)*100:.1f}%" if v.get('vaf') is not None else "N/A", styles['TableCell']),
                Paragraph(str(v.get("depth", "N/A")), styles['TableCell'])
            ])
        else:
            table_data.append([
                Paragraph(highlight_gene_text(v.get("gene", "")), styles['TableCell']),
                Paragraph(v.get("hgvs", ""), styles['TableCell']),
                Paragraph(f"<i>{v.get('classification', 'Relevanz unklar')}</i>", styles['TableCell']),
                Paragraph(f"{v.get('vaf', 0)*100:.1f}%" if v.get('vaf') is not None else "N/A", styles['TableCell']),
                Paragraph(str(v.get("depth", "N/A")), styles['TableCell'])
            ])

    # Table styling
    target_width = doc_width * TABLE_WIDTH_FACTOR
    col_widths = [p * target_width for p in proportions]
    
    ts = TableStyle([
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('INNERGRID', (0, 0), (-1, -1), 0.25, BLACK),
        ('BOX', (0, 0), (-1, -1), 0.5, BLACK),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [WHITE, LIGHT_GREY]),
        ('ALIGN', (vaf_col_idx, 0), (-1, -1), 'CENTER'),
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor("#EEEEEE")),
    ])

    if is_qc:
        # Reduce spacing for QC rows
        ts.add('TOPPADDING', (0, 1), (-1, -1), 1)
        ts.add('BOTTOMPADDING', (0, 1), (-1, -1), 0)
        ts.add('LEFTPADDING', (0, 1), (-1, -1), 2)
        ts.add('RIGHTPADDING', (0, 1), (-1, -1), 2)

    table = Table(table_data, colWidths=col_widths, hAlign='CENTER', repeatRows=1)
    table.setStyle(ts)
    return table


def generate_main_variants_section(doc_width, styles, variants_data):
    """Generates the main Gene variants section."""
    story = []
    story.extend(create_section_header("Gene variants", styles))
    
    variants = variants_data.get("variants", [])
    main_vars = [v for v in variants if v.get("is_main_candidate")]
    
    if not main_vars:
        story.append(Paragraph("No significant variants detected after filtering.", styles['Normal']))
    else:
        table = create_variant_table(main_vars, styles, doc_width, is_qc=False)
        if table:
            story.append(table)

    if story:
        story[-1].spaceAfter = SECTION_SPACING
    return story

def generate_qc_variants_section(doc_width, styles, variants_data):
    """Generates the QC variants subsection for the Supplementary section."""
    story = []
    variants = variants_data.get("variants", [])
    qc_vars = [v for v in variants if not v.get("is_main_candidate")]
    
    if qc_vars:
        story.append(Paragraph("All detected variants", styles['SubHeader']))
        table = create_variant_table(qc_vars, styles, doc_width, is_qc=True)
        if table:
            story.append(table)

        # Add Unified Comments to QC variants
        comments = variants_data.get("comments", [])
        if comments:
            story.append(Spacer(1, 4))
            for c in comments:
                c_text = f"<b>{c['gene']} {c['hgvsc']}:</b> {c['comment']}"
                if c.get("date"):
                    c_text += f" (<i>{c['date']}</i>)"
                story.append(Paragraph(c_text, styles['TableCell']))

        if story:
            story[-1].spaceAfter = SECTION_SPACING
            
    return story


# --- Main Execution ---
def main():
    parser = argparse.ArgumentParser(description="Generate an NGS report PDF.")
    parser.add_argument("relative_dir_path", help="Path to sample directory.")
    parser.add_argument("file_prefix", help="Prefix for output PDF.")
    parser.add_argument("--variants-json", help="Path to processed variants JSON file.")
    args = parser.parse_args()

    base_dir = os.path.abspath(args.relative_dir_path)
    output_file = os.path.join(base_dir, f"{args.file_prefix}_ngs_report.pdf")

    if not os.path.isdir(base_dir):
        print(f"Error: Directory not found: {base_dir}")
        return

    print(f"Reading data from: {base_dir}")
    print(f"Writing report to: {output_file}")


    is_metagenomics_sample = False
    cnv_dir = os.path.join(base_dir, 'cnv')
    coverage_dir = os.path.join(cnv_dir, 'coverage')
    panel_coverage_file = get_file_path(coverage_dir, "*_panel_coverage.txt")
    
    if panel_coverage_file:
        try:
            df_cov = pd.read_csv(panel_coverage_file, sep='\t', header=None, usecols=[2])
            if not df_cov.empty:
                mean_coverage = df_cov[2].mean()
                print(f"Info: Mean panel coverage is {mean_coverage:.2f}")
                if mean_coverage < 100:
                    is_metagenomics_sample = True
                    print("Info: Low coverage detected. Treating sample as Metagenomics.")
            else:
                print("Warning: Panel coverage file is empty.")
        except Exception as e:
            print(f"Warning: Could not process panel coverage file '{panel_coverage_file}': {e}")
    else:
        print("Warning: Panel coverage text file not found. Assuming standard NGS sample.")


    doc = create_pdf_document(output_file)
    doc.file_prefix = args.file_prefix
    doc.is_metagenomics_sample = is_metagenomics_sample

    styles = getSampleStyleSheet()
    styles.add(ParagraphStyle('SectionHeader', fontName='Helvetica-Bold', fontSize=11, textColor=BLACK, spaceAfter=2, keepWithNext=True))
    styles.add(ParagraphStyle('SubHeader', fontName='Helvetica-Bold', fontSize=9, textColor=BLACK, spaceBefore=6, spaceAfter=2, keepWithNext=True))
    styles.add(ParagraphStyle('TableCell', fontName='Helvetica', fontSize=7, leading=9))
    styles['Normal'].fontName = 'Helvetica'
    styles['Normal'].fontSize = 7

    story = []
    story.extend(generate_qc_section(base_dir, doc.width, styles))

    # Load fusion genes for highlighting
    fusion_genes = []
    fusion_genes_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "resources", "fusion_genes.csv")
    if os.path.exists(fusion_genes_path):
        try:
            df_fg = pd.read_csv(fusion_genes_path)
            fusion_genes = df_fg['gene'].tolist()
        except Exception as e:
            print(f"Warning: Could not load fusion genes from {fusion_genes_path}: {e}")

    # Variants Section - Moved to top after QC
    variants_dir = os.path.join(base_dir, 'variants')
    variants_json = get_file_path(variants_dir, "*_variants_processed.json")
    variants_data = None
    
    if variants_json and os.path.exists(variants_json):
        try:
            with open(variants_json, 'r', encoding='utf-8') as f:
                variants_data = json.load(f)
            story.extend(generate_main_variants_section(doc.width, styles, variants_data))
        except Exception as e:
            print(f"Warning: Could not load variants JSON: {e}")
            story.extend(create_section_header("Gene variants", styles))
            story.append(Paragraph(f"Error loading variants: {e}", styles['Normal']))
    
    story.extend(generate_cnv_section(base_dir, doc.width, styles, is_metagenomics=is_metagenomics_sample))
    story.extend(generate_fusions_section(base_dir, doc.width, styles, fusion_genes=fusion_genes))

    # Add Supplementary section at the end
    supplementary_story = []
    
    # 1. QC Variants (All detected variants)
    if variants_data:
        supplementary_story.extend(generate_qc_variants_section(doc.width, styles, variants_data))
    
    # 2. Focal plots
    focal_story = generate_focal_cnv_section(base_dir, doc.width, styles)
    if focal_story:
        supplementary_story.extend(focal_story)

    if supplementary_story:
        story.extend(create_section_header("Supplementary", styles))
        story.extend(supplementary_story)


    try:
        doc.build(story)
        print("PDF created successfully.")
    except Exception as e:
        print(f"Error during PDF build: {e}")

if __name__ == '__main__':
    main()