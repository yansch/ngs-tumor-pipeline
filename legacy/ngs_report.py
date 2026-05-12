#!/usr/bin/env python3

import argparse
import os
import glob
import pandas as pd
import re
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

def highlight_gene_text(text, gene_list, color="red"):
    """Highlights specific gene names within a string for ReportLab Paragraphs."""
    if not isinstance(text, str): return text
    escaped_text = escape(text)
    parts = escaped_text.split(',')
    out = []
    for p in parts:
        trimmed = p.strip()
        if any(g in trimmed for g in gene_list):
            out.append(f'<font color="{color}"><b>{trimmed}</b></font>')
        else:
            out.append(trimmed)
    return ", ".join(out)

def create_styled_table(df, styles, table_style, col_widths=None, hAlign='LEFT'):
    """Creates a styled ReportLab Table from a pandas DataFrame, applying a given style."""
    header = [Paragraph(f'<b>{col}</b>', styles['TableCell']) for col in df.columns]
    
    data_rows = []
    for _, row in df.iterrows():
        data_row = [item if isinstance(item, Paragraph) else Paragraph(str(item), styles['TableCell']) for item in row]
        data_rows.append(data_row)
        
    table = Table([header] + data_rows, colWidths=col_widths, hAlign=hAlign, repeatRows=1)
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
    # (QC section remains unchanged)
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

    return [KeepTogether(section_content)]


def generate_cnv_section(directory, doc_width, styles, is_metagenomics=False):
    story = create_section_header("Copy number profile", styles)
    story.append(Paragraph(f"Reference: {CNV_REFERENCE_FILE} ({CNV_REFERENCE_DATE})", styles['Normal']))
    cnvdir = os.path.join(directory, 'cnv')

    plot = get_file_path(cnvdir, "cnv_plot.png")
    if plot and (img := get_proportional_image(plot, doc_width)):
        story.append(KeepTogether([Paragraph("Genome-wide copy number profile", styles['SubHeader']), img]))
    else:
        story.append(Paragraph("Global CNV plot not found.", styles['Normal']))

    story.append(Spacer(1, SUB_SECTION_SPACING))
    
    f1, f2 = get_file_path(cnvdir, "EGFR_MET.png"), get_file_path(cnvdir, "CDKN2A.png")
    if f1 and f2:
        i1, i2 = get_proportional_image(f1, doc_width * 0.49), get_proportional_image(f2, doc_width * 0.49)
        if i1 and i2:
            focal_table = Table([[i1, i2]], colWidths=[doc_width * 0.5] * 2, style=[('VALIGN', (0, 0), (-1, -1), 'TOP')])
            story.append(KeepTogether([Paragraph("Focal analysis of chr7 (EGFR, MET) and chr9 (CDKN2A)", styles['SubHeader']), focal_table]))
    
    # --- MODIFIED: Conditionally skip panel coverage plot ---
    if not is_metagenomics:
        cov = get_file_path(os.path.join(directory, 'cnv'), "*_panel_coverage.png")
        if cov and (ci := get_proportional_image(cov, doc_width * 0.8)):
            ci.hAlign = 'CENTER'
            story.append(Spacer(1, SUB_SECTION_SPACING))
            story.append(KeepTogether([Paragraph("Panel coverage", styles['SubHeader']), ci]))
    else:
        print("Info: Metagenomics sample detected. Skipping panel coverage plot.")

    if story:
        story[-1].spaceAfter = SECTION_SPACING
    return story

def generate_fusions_section(directory, doc_width, styles):
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
                df = df[['#gene1', 'gene2', 'split_reads1', 'split_reads2', 'discordant_mates', 'confidence']].copy()
                df.columns = ["Gene 1", "Gene 2", "Split Reads 1", "Split Reads 2", "Discordant Reads", "Confidence"]
                
                for col in ["Gene 1", "Gene 2"]:
                    df[col] = df[col].apply(lambda x: Paragraph(highlight_gene_text(x, HIGHLIGHT_GENES, "red"), styles['TableCell']))
                
                fusions_table_style = TableStyle([
                    ('ROWBACKGROUNDS', (0, 1), (-1, -1), [WHITE, LIGHT_GREY]),
                    ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
                    ('INNERGRID', (0, 0), (-1, -1), 0.25, BLACK),
                    ('BOX', (0, 0), (-1, -1), 0.5, BLACK)
                ])
                
                target_width = doc_width * TABLE_WIDTH_FACTOR
                proportions = [0.25, 0.25, 0.1, 0.1, 0.15, 0.15]
                col_widths = [p * target_width for p in proportions]
                story.append(create_styled_table(df, styles, fusions_table_style, col_widths=col_widths, hAlign='CENTER'))
        except Exception as e:
            story.append(Paragraph(f"Could not process fusion file: {e}", styles['Normal']))

    if story:
        story[-1].spaceAfter = SECTION_SPACING
    return story

def generate_metagenomics_section(directory, doc_width, styles):
    # (Metagenomics section remains unchanged)
    metagenomics_table_style = TableStyle([
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [WHITE, LIGHT_GREY]),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('BOX', (0, 0), (-1, -1), 0.5, BLACK),
    ])
    data_flowables = []
    target_width = doc_width * TABLE_WIDTH_FACTOR

    vf = get_file_path(os.path.join(directory, 'arriba'), "*virus_expression.tsv")
    if vf:
        try:
            df = pd.read_csv(vf, sep='\t')
            if not df.empty:
                df = df[['VIRUS', 'COVERED_GENOME_FRACTION', 'HIGH_QUALITY_ALIGNMENTS']]
                df.columns = ["Virus", "Genome Fraction", "High Quality Alignments"]
                df['Virus'] = df['Virus'].str.replace('_', ' ')

                proportions = [0.45, 0.25, 0.30]
                col_widths = [p * target_width for p in proportions]
                data_flowables.append(create_styled_table(
                    df, styles, metagenomics_table_style, col_widths=col_widths, hAlign='CENTER'
                ))
        except Exception as e:
            print(f"Warning: Could not process virus expression file '{vf}': {e}")

    kf = get_file_path(os.path.join(directory, 'kraken'), "*.krakenuniq.report.txt")
    if kf:
        try:
            kraken_content = []
            kraken_threshold = 3

            df_full = pd.read_csv(kf, sep='\t', comment='#')
            df_species = df_full[df_full['rank'] == 'species'].copy()
            
            df_filtered, removed_count = filter_kraken_results(df_species, kraken_threshold)

            if not df_filtered.empty:
                df_sorted = df_filtered.sort_values('cov', ascending=False)
                out = pd.DataFrame({
                    'Name': df_sorted['taxName'].str.replace('_', ' '),
                    'Reads': df_sorted['reads'],
                    'Coverage': (df_sorted['cov'] * 100).round(2),
                    'Percent': df_sorted['%'].round(2)
                })
                proportions = [0.55, 0.15, 0.15, 0.15]
                col_widths = [p * target_width for p in proportions]
                kraken_content.append(create_styled_table(
                    out, styles, metagenomics_table_style, col_widths=col_widths, hAlign='CENTER'
                ))

            if removed_count > 0:
                p = Paragraph(f"Filtered out {removed_count} results with number of reads < {kraken_threshold}", styles['Normal'])
                p.spaceBefore = 0.1 * inch
                kraken_content.append(p)

            if kraken_content:
                data_flowables.extend(kraken_content)

        except Exception as e:
            print(f"Warning: Could not process kraken file '{kf}': {e}")

    if not data_flowables:
        print("Info: No metagenomics data found. Skipping section.")
        return []

    story = create_section_header("Metagenomics", styles)
    story.extend(data_flowables)
    if story:
        story[-1].spaceAfter = SECTION_SPACING
        
    return story

# --- Main Execution ---
def main():
    parser = argparse.ArgumentParser(description="Generate an NGS report PDF.")
    parser.add_argument("relative_dir_path", help="Path to sample directory.")
    parser.add_argument("file_prefix", help="Prefix for output PDF.")
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
    panel_coverage_file = get_file_path(cnv_dir, "*_panel_coverage.txt")
    
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
    story.extend(generate_cnv_section(base_dir, doc.width, styles, is_metagenomics=is_metagenomics_sample))
    story.extend(generate_fusions_section(base_dir, doc.width, styles))
    story.extend(generate_metagenomics_section(base_dir, doc.width, styles))

    try:
        doc.build(story)
        print("PDF created successfully.")
    except Exception as e:
        print(f"Error during PDF build: {e}")

if __name__ == '__main__':
    main()