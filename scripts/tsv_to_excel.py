#!/usr/bin/env python3
import sys
import os
import pandas as pd
from openpyxl.styles import Font

def main():
    if len(sys.argv) < 3:
        print("Usage: tsv_to_excel.py <input_tsv> <output_xlsx>")
        sys.exit(1)

    input_tsv = sys.argv[1]
    output_xlsx = sys.argv[2]

    if not os.path.exists(input_tsv):
        print(f"Error: Input file '{input_tsv}' does not exist.", file=sys.stderr)
        sys.exit(1)

    # Load highlight genes
    fusion_genes = set()
    script_dir = os.path.dirname(os.path.abspath(__file__))
    fusion_genes_path = os.path.abspath(os.path.join(script_dir, "..", "resources", "fusion_genes.csv"))
    if os.path.exists(fusion_genes_path):
        try:
            df_fg = pd.read_csv(fusion_genes_path)
            if 'gene' in df_fg.columns:
                fusion_genes = set(df_fg['gene'].dropna().astype(str).str.strip().str.upper().tolist())
            print(f"Loaded {len(fusion_genes)} highlight genes from {fusion_genes_path}")
        except Exception as e:
            print(f"Warning: Could not load fusion genes: {e}", file=sys.stderr)

    try:
        # Read TSV
        df = pd.read_csv(input_tsv, sep='\t')

        # Clean column names (specifically arriba's '#gene1')
        rename_dict = {}
        for col in df.columns:
            if col.startswith('#'):
                rename_dict[col] = col.lstrip('#').strip()
        if rename_dict:
            df = df.rename(columns=rename_dict)

        # Write to excel with column auto-fitting and highlighting
        with pd.ExcelWriter(output_xlsx, engine='openpyxl') as writer:
            df.to_excel(writer, index=False, sheet_name="Sheet1")
            
            worksheet = writer.sheets["Sheet1"]
            
            # Find the indices of columns named 'gene1' and 'gene2'
            gene_col_indices = []
            for i, col_name in enumerate(df.columns):
                if col_name in ['gene1', 'gene2']:
                    gene_col_indices.append(i + 1) # 1-based indexing for openpyxl
            
            highlight_font = Font(bold=True, color="FF0000") # Red and Bold
            
            # Auto-fit column widths and apply font formatting to matching genes
            for col_idx, col in enumerate(worksheet.columns, start=1):
                max_len = 0
                col_letter = col[0].column_letter
                for cell_idx, cell in enumerate(col, start=1):
                    val_to_check = str(cell.value or '')
                    if cell.value is not None:
                        # If there are linebreaks, take the max line length
                        max_len = max(max_len, max(len(line) for line in val_to_check.split('\n')))
                        
                        # Apply style if cell is in gene column and not header
                        if col_idx in gene_col_indices and cell_idx > 1:
                            if val_to_check.strip().upper() in fusion_genes:
                                cell.font = highlight_font
                                
                worksheet.column_dimensions[col_letter].width = max(max_len + 3, 10)

        print(f"Successfully converted '{input_tsv}' to '{output_xlsx}'")

    except Exception as e:
        print(f"Error converting TSV to Excel: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
