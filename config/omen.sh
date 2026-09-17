#!/bin/bash
# config/omen.sh - Omen-specific configuration

export HAS_MODULE_SYSTEM=false

# --- Path Additions ---
export PATH="/software/arriba_v2.5.1/bin:$PATH"

# --- Reference Base Paths ---
export BASE_DIR="/software/arriba_v2.5.1"
export REF_DIR="$BASE_DIR/references_hg19"
export ARRIBA_LIB="$BASE_DIR/var/lib/arriba"
export CNV_REF_DIR="/mnt/pipelines/ngs-tumor-pipeline/resources"
export REF_BASE="/software"
export VENV_PATH="/mnt/pipelines/ngs-tumor-pipeline/env"

# --- Explicit Binary Track ---
export BWA_BIN="$VENV_PATH/bin/bwa-mem2"
export BOWTIE2_BIN="bowtie2"

# --- Specific Reference Files ---
export REF_GENOME="$REF_DIR/hs37d5viral.fa"
export STAR_INDEX="$REF_DIR/STAR_index_hs37d5viral_GENCODE19"
export STAR_INDEX_ARRIBA="$STAR_INDEX"
export REF_GENOME_CNV="$REF_DIR/hg19.fa"
export ANNOTATION_GTF="$REF_DIR/GENCODE19.gtf"
export ASSEMBLY_FA="$REF_DIR/hs37d5viral.fa"
export ARRIBA_BLACKLIST="$ARRIBA_LIB/blacklist_hg19_hs37d5_GRCh37_v2.5.1.tsv.gz"
export ARRIBA_KNOWN_FUSIONS="$ARRIBA_LIB/known_fusions_hg19_hs37d5_GRCh37_v2.5.1.tsv.gz"
export ARRIBA_TAGS="$ARRIBA_KNOWN_FUSIONS"
export ARRIBA_PROTEIN_DOMAINS="$ARRIBA_LIB/protein_domains_hg19_hs37d5_GRCh37_v2.5.1.gff3"
export ARRIBA_CYTOBANDS="$ARRIBA_LIB/cytobands_hg19_hs37d5_GRCh37_v2.5.1.tsv"

# CNVkit & Custom Resources
export CNV_REFERENCE="$CNV_REF_DIR/panel_v4.1_reference.cnn"
export RELEVANT_GENES="$CNV_REF_DIR/relevant_genes.csv"
export CYTOBAND_TXT="$CNV_REF_DIR/cytoBand.txt"
export PANEL_REGIONS="$CNV_REF_DIR/panel_v4.1_hg19.csv"

# Metagenomics host depletion reference
export BOWTIE_INDEX="$REF_BASE/metagenomics/bowtie_index/chm13v2.0"

# --- Resource Allocation ---
export PIPELINE_THREADS=32
export PIPELINE_MEM="64G"
export SORT_MEM_BASE=20000
export FILE_TRANSFER_WAIT_TIME=2 # in minutes

# --- Runtime & Output Paths ---
export SCRATCH_DIR="${SCRATCH_DIR:-/data/ngs-tumor-pipeline}"
export INPUT_DIR="${INPUT_DIR:-$SCRATCH_DIR/input}"
export VARIANTS_SEARCH_DIR="${VARIANTS_SEARCH_DIR:-$INPUT_DIR}"
export RESULTS_BASE="${RESULTS_BASE:-$SCRATCH_DIR/output}"

# --- Local Notification (Progress Display) ---
export DISPLAY="${DISPLAY:-:0}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/1000/bus}"

_notification_dir="$PROJECT_DIR/components/11_local_notification"
export NOTIFICATION_DIR="$_notification_dir"
_analysis_gui_ctrl="$_notification_dir/.analysis_gui_ctrl"
_analysis_gui_pid="$HOME/.analysis_gui.pid"

Environment_Initialized=false
Overall_Step=0
Case_Step=0

analysis_gui_start() {
    export DISPLAY="${DISPLAY:-:0}"
    export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/1000/bus}"

    pkill -f 'analysis_progress_gui.py' 2>/dev/null || true
    sleep 0.2

    rm -f "$_analysis_gui_ctrl"
    python3 "$_notification_dir/analysis_progress_gui.py" &
    echo $! > "$_analysis_gui_pid"
}

analysis_gui_update() {
    local cmd="${1:-}"
    local pct="${2:-0}"
    local text="${3:-}"

    local json
    case "$cmd" in
        overall|case)
            if [[ -n $text ]]; then
                text=$(printf '%s' "$text" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')
                json="{\"cmd\":\"$cmd\",\"value\":$pct,\"text\":$text}"
            else
                json="{\"cmd\":\"$cmd\",\"value\":$pct}"
            fi
            ;;
        title)
            text=$(printf '%s' "$pct" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')
            json="{\"cmd\":\"title\",\"value\":$text}"
            ;;
        stop)
            json='{"cmd":"close"}'
            ;;
        *)
            echo "Usage: analysis_gui_update {overall|case|title|stop} [value] [text]" >&2
            return 1
            ;;
    esac

    printf '%s\n' "$json" >> "$_analysis_gui_ctrl"
}

analysis_gui_stop() {
    analysis_gui_update stop
    if [[ -f "$_analysis_gui_pid" ]]; then
        kill "$(cat "$_analysis_gui_pid")" 2>/dev/null || true
        rm -f "$_analysis_gui_pid"
    fi
    pkill -f 'analysis_progress_gui.py' 2>/dev/null || true
    rm -f "$_analysis_gui_ctrl"
}

# Helper to count pipeline modules (steps) under components/
count_pipeline_modules() {
    local base="$PROJECT_DIR/components"
    local count=0
    local d name

    for d in "$base"/*/; do
        [[ -d $d ]] || continue
        name=$(basename "$d")
        [[ $name == "*" ]] && continue

        # Skip local notification component
        if [[ $name == *local_notification* ]]; then
            continue
        fi

        ((count++))
    done

    echo "$count"
}

export TOTAL_PIPELINE_MODULES=$(count_pipeline_modules)

Calc_Frac() {
    local step="$1"
    local total_steps="$2"

    awk -v s="$step" -v S="$total_steps" \
        'BEGIN {
            if (S == 0) { printf "0"; exit }
            frac = s / S;
            printf "%.0f", frac * 100
        }'
}

Update_Case() {
    local Case="$1"
    local Module="${2:-""}"
    
    if [ -z "${Case_Step:-}" ]; then
        Case_Step=0
    fi
    
    if [ "$Module" == "fastp" ]; then
        Case_Step=1
    fi
    Case_PCT=$(Calc_Frac "$Case_Step" "$TOTAL_PIPELINE_MODULES")
    analysis_gui_update case "$Case_PCT" "Case ${CASE_LABEL:-$Case}: Step $Case_Step/$TOTAL_PIPELINE_MODULES completed"
    (( Case_Step++ )) || true
    
    sleep 0.2

    if [ "$Case_Step" -gt "$TOTAL_PIPELINE_MODULES" ]; then
        analysis_gui_update case "$Case_PCT" "Case ${CASE_LABEL:-$Case}: Step $Case_Step/$TOTAL_PIPELINE_MODULES completed"
        unset Case_Step
    fi    
}

Update_Overall() {
    if [[ $Environment_Initialized == false ]]; then
        analysis_gui_start
        analysis_gui_update overall 0 "Overall: 0% (Case 0 of ${amount:-0} analyzed)"
        Environment_Initialized=true
    elif [[ $Environment_Initialized == true ]]; then 
        if [ -z "${Overall_Step:-}" ]; then
            Overall_Step=1
        fi

        if [ -n "${Overall_Step:-}" ]; then
            Overall_PCT=$(Calc_Frac "$submitted" "${amount:-1}")
            analysis_gui_update overall "$Overall_PCT" "Overall: $Overall_PCT% (Case $submitted of ${amount:-0} analyzed)"
            Overall_Step=$((Overall_Step + 1))
        fi

        if [ -n "${Overall_Step:-}" ]; then
            if [ "$Overall_Step" -eq "${amount:-0}" ]; then
                unset Overall_Step
            fi    
        fi

        if [ "$submitted" -eq "${amount:-0}" ]; then
            analysis_gui_update overall 100 "All cases analyzed."
            analysis_gui_update case 100 "Done."
            sleep 2
            analysis_gui_stop    
        fi
    fi
}

