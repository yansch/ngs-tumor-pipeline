#!/usr/bin/env bash
# notification_test.sh - Simulation test for decoupled pipeline status tracking & notifications
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_DIR="${PROJECT_DIR:-$SCRIPT_DIR}"
source "$PROJECT_DIR/config/common.sh"

echo "🧪 Starting notification & status tracker test simulation..."

total_cases=3
status_init "$total_cases" "/data/test_input"
status_gui_start

steps=("01 · fastp" "02 · STAR" "03 · BWA-MEM2" "04 · Arriba" "05 · CNVkit" "06 · CNV plots" "07 · Coverage" "08 · Variants" "09 · PDF report")

for ((case_num=1; case_num<=total_cases; case_num++)); do
    case_label="Test_Sample_0${case_num}"
    status_case_start "$case_label" "$case_num" "$total_cases"
    echo "▶ Simulating $case_label ($case_num/$total_cases)..."

    for step in "${steps[@]}"; do
        status_step_update "$step" "running"
        sleep 0.3
        status_step_update "$step" "done"
        sleep 0.2
    done
done

echo "✅ Simulation complete. Calling status_finish..."
status_finish "$total_cases" 0
echo "Done! Check /tmp/ngs_pipeline_status.json and GUI window."