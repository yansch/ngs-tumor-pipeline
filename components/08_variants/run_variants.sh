#!/bin/bash
# components/08_variants/run_variants.sh
# Step 8: Variant processing — filtering, OncoKB classification, Excel output
#
# Expects (set by orchestrator):
#   CASE_LABEL, OUT_DIR, PROJECT_DIR
#   VARIANTS_SEARCH_DIR
#   (Analysis env + venv already activated by orchestrator)
#
# Exports:
#   VAR_ARG  - "--variants-json <path>" flag passed to the report step,
#              or empty string if no variants file was found

require_vars CASE_LABEL OUT_DIR PROJECT_DIR VARIANTS_SEARCH_DIR

_STEP_T0=$(date +%s)
step_start "08 · Variants — filtering & OncoKB annotation"

_VARIANT_SCRIPT="$PROJECT_DIR/components/08_variants/ngs_variant_processor.py"

VARIANTS_JSON="${VARIANTS_SEARCH_DIR}/${CASE_LABEL}.json.gz"
if [ ! -f "$VARIANTS_JSON" ]; then
    VARIANTS_JSON="${VARIANTS_SEARCH_DIR}/${CASE_LABEL}.json"
fi

# Fallback: fuzzy prefix search
if [ ! -f "$VARIANTS_JSON" ]; then
    echo "   Searching for matching variant file in $VARIANTS_SEARCH_DIR..."
    for f in "$VARIANTS_SEARCH_DIR"/*.hard-filtered.vcf.annotated.json*; do
        [ -e "$f" ] || continue
        fname=$(basename "$f")
        prefix="${fname%%.hard-filtered*}"
        if [[ "$CASE_LABEL" == *"$prefix"* ]]; then
            echo "   Found match by prefix: $prefix → $fname"
            VARIANTS_JSON="$f"
            break
        fi
    done
fi

VARIANTS_DIR="$OUT_DIR/variants"
mkdir -p "$VARIANTS_DIR"
PROCESSED_VARS="$VARIANTS_DIR/${CASE_LABEL}_variants_processed.json"
VAR_ARG=""

if [ -f "$VARIANTS_JSON" ]; then
    if run_if_missing "$PROCESSED_VARS" "variant processing"; then
        echo "   Processing variants: $(basename "$VARIANTS_JSON")"
        python "$_VARIANT_SCRIPT" \
            "$VARIANTS_JSON" \
            --ref-dir "$PROJECT_DIR/resources" \
            -o "$PROCESSED_VARS"
    fi
    VAR_ARG="--variants-json $PROCESSED_VARS"
else
    echo "   ℹ️  No variant JSON found for $CASE_LABEL — skipping variant processing."
fi

export VAR_ARG

step_end "08 · Variants" "$_STEP_T0"
