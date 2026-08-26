#!/bin/bash
# components/04_arriba/run_arriba.sh
# Step 4: Arriba fusion detection, visualization, and virus expression quantification
#
# Expects (set by orchestrator):
#   BAM_FILE_ARRIBA, OUT_DIR, R1_base, TMP_DIR
#   ARRIBA_OUT, ANNOTATION_GTF
#   ARRIBA_BASE, ARRIBA_BLACKLIST, ARRIBA_KNOWN_FUSIONS, ARRIBA_TAGS,
#   ARRIBA_PROTEIN_DOMAINS, ARRIBA_CYTOBANDS
#   REF_GENOME_ARRIBA (optional, falls back to REF_GENOME)
#   ANNOTATION_GTF_ARRIBA (optional, falls back to ANNOTATION_GTF)
#   ANALYSIS_TOOLCHAIN_MODULE, ARRIBA_VISUALIZATION_MODULES[@]

require_vars BAM_FILE_ARRIBA OUT_DIR R1_base ARRIBA_OUT ANNOTATION_GTF

_STEP_T0=$(date +%s)
step_start "04 · Arriba — fusion detection"

if run_if_missing "$ARRIBA_OUT" "Arriba fusion detection"; then

    # --- Resolve binaries ---
    ARRIBA_BIN="arriba"
    if [ -f "$ARRIBA_BASE/arriba" ]; then
        ARRIBA_BIN="$ARRIBA_BASE/arriba"
    fi

    REF_GENOME_FOR_ARRIBA="${REF_GENOME_ARRIBA:-$REF_GENOME}"
    ANNOTATION_GTF_FOR_ARRIBA="${ANNOTATION_GTF_ARRIBA:-$ANNOTATION_GTF}"

    echo "   Running Arriba fusion detection..."
    "$ARRIBA_BIN" \
        -x "$BAM_FILE_ARRIBA" \
        -o "$ARRIBA_OUT" \
        -f intronic,in_vitro,internal_tandem_duplication \
        -a "$REF_GENOME_FOR_ARRIBA" \
        -g "$ANNOTATION_GTF_FOR_ARRIBA" \
        -b "$ARRIBA_BLACKLIST" \
        -k "$ARRIBA_KNOWN_FUSIONS" \
        -t "$ARRIBA_TAGS" \
        -p "$ARRIBA_PROTEIN_DOMAINS"

    # --- Visualization (draw_fusions.R) ---
    purge_modules
    load_modules "$ANALYSIS_TOOLCHAIN_MODULE" "${ARRIBA_VISUALIZATION_MODULES[@]}"

    DRAW_FUSIONS_R="draw_fusions.R"
    if [ -f "$ARRIBA_BASE/draw_fusions.R" ]; then
        DRAW_FUSIONS_R="$ARRIBA_BASE/draw_fusions.R"
    elif [ -f "$BASE_DIR/bin/draw_fusions.R" ]; then
        DRAW_FUSIONS_R="$BASE_DIR/bin/draw_fusions.R"
    fi

    echo "   Generating fusion visualization PDF..."
    "$DRAW_FUSIONS_R" \
        --fusions="$ARRIBA_OUT" \
        --alignments="$BAM_FILE_ARRIBA" \
        --output="$OUT_DIR/arriba/${R1_base}_fusions.pdf" \
        --annotation="$ANNOTATION_GTF" \
        --cytobands="$ARRIBA_CYTOBANDS" \
        --proteinDomains="$ARRIBA_PROTEIN_DOMAINS"

    # --- Virus expression quantification (optional, Omen feature) ---
    QUANTIFY_VIRUS_SH="quantify_virus_expression.sh"
    if [ -f "$ARRIBA_BASE/quantify_virus_expression.sh" ]; then
        QUANTIFY_VIRUS_SH="$ARRIBA_BASE/quantify_virus_expression.sh"
    elif [ -f "$BASE_DIR/bin/quantify_virus_expression.sh" ]; then
        QUANTIFY_VIRUS_SH="$BASE_DIR/bin/quantify_virus_expression.sh"
    fi

    if command -v "$QUANTIFY_VIRUS_SH" &>/dev/null || [ -f "$QUANTIFY_VIRUS_SH" ]; then
        echo "   Quantifying virus expression..."
        "$QUANTIFY_VIRUS_SH" \
            "$BAM_FILE_ARRIBA" \
            "$OUT_DIR/arriba/${R1_base}_virus_expression.tsv" || true
    fi
fi

step_end "04 · Arriba" "$_STEP_T0"
