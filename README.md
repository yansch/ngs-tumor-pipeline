# 🧬 NGS Tumor Pipeline

An automated, end-to-end pipeline for Next-Generation Sequencing (NGS) tumor analysis, optimized for High-Performance Computing (HPC) clusters (**PALMA II** and **Omen**).

---

## 🚀 Key Features

* **Complete Analysis Workflow**: FASTQ trimming, dual alignment (RNA & DNA), fusion detection, copy number variation (CNV) calling, target coverage plotting, variant filtering & OncoKB annotation, non-human read extraction, and automated Excel report generation.
* **Dual Execution Modes**:
  * **Palma (HPC Slurm)**: Multi-branch parallel execution (STAR+Arriba, BWA+CNVkit+Plots+Coverage+Metagenomics, Variants+OncoKB) with dynamic Slurm CPU allocation.
  * **Omen (Local/Workstation)**: Sequential execution mode.
* **Smart Orchestration**: Interactive remote update check, input file transfer safety detection, case filtering (`--only`), and configuration runtime overrides.
* **Slurm Job Monitoring**: Live status dashboard (`monitor_jobs.sh`) displaying real-time Slurm job states, estimated remaining runtimes based on FASTQ sizes, and job history.

---

## 📥 Step 1: Clone the Repository

Clone the repository into your HPC scratch space:

```bash
cd /scratch/tmp/$USER
git clone https://github.com/yansch/ngs-tumor-pipeline.git
cd ngs-tumor-pipeline
```

---

## 🛠️ Step 2: Installation & Setup

Run the automated setup script. It auto-detects cluster environments, loads required modules, sets up a private Python virtual environment, and installs pipeline dependencies:

```bash
bash setup.sh
```

During setup, you will be prompted for an optional **OncoKB API token**. Paste your token to save it securely in `.env`, or press `Enter` to skip/keep the current token. You can re-run `setup.sh` at any time to update your token.

---

## 🧪 Step 3: Running the Pipeline

### 1. Prepare Your Data

By default, place your FASTQ (`*_R1_001.fastq.gz`, `*_R2_001.fastq.gz`) and optional VCF files in the `input/` folder:

```bash
# Example for Palma
cp /path/to/your/files/*.fastq.gz /scratch/tmp/$USER/ngs-tumor-pipeline/input/
```

*(Alternatively, you can pass a custom input directory directly to `run.sh`.)*

### 2. Launch the Analysis

Run the orchestrator script to scan input files and launch pipeline jobs:

```bash
# Default run (scans ./input)
bash run.sh

# Or specify a custom input directory
bash run.sh /path/to/my_input_folder
```

On launch, `run.sh` checks for updates on `origin/main`. If new commits exist, it displays the commit log and prompts if you wish to update (`[y/N]`).

---

### 🎛️ Command-Line Options & Flags

`run.sh` supports the following flags (accepts both space-separated and `--flag=value` syntax):

| Flag | Argument | Description |
| :--- | :--- | :--- |
| `--only` | `<case_id>` | Analyze only cases matching a specific case identifier or substring. |
| `--dry-run` | *(none)* | Scan input directory and display detected cases without submitting jobs. |
| `--keep-existing` | *(none)* | Preserve previous `tmp/` and `output/` directories instead of clearing them. |
| `--now` | *(none)* | Skip remote update check and active file transfer safety delay. |
| `--mail-user` | `<email>` | Send Slurm job status notifications (`--mail-type=ALL`) to the specified email. |
| `--set` | `KEY=VALUE` | Override any scalar configuration variable at runtime (repeatable). |
| `--overrides-file` | `<path>` | Source a custom Bash overrides file after host configuration. |
| `--help`, `-h` | *(none)* | Show command usage and options summary. |

#### Examples:

```bash
# Filter specific case and receive Slurm email updates
bash run.sh --only CASE123 --mail-user user@uni-muenster.de

# Run immediately, bypassing file transfer wait time and update checks
bash run.sh --now

# Override configuration variables on CLI
bash run.sh --set PIPELINE_THREADS=32 --set RESULTS_BASE=/scratch/tmp/$USER/ngs-output

# Use a custom configuration file for array/module overrides
bash run.sh --overrides-file /path/to/custom-overrides.sh
```

#### Configuration Precedence:
1. Host defaults (`config/omen.sh` or `config/palma.sh`)
2. `.env` file (local tokens/secrets)
3. `--overrides-file`
4. `--set` CLI overrides

---

## 📊 Step 4: Monitoring Jobs (Palma)

On Palma, monitor active Slurm jobs, runtime estimations, log output paths, and job histories using `monitor_jobs.sh`:

```bash
# Live monitoring dashboard (auto-refreshes every 10 seconds by default)
bash monitor_jobs.sh

# Change refresh interval (e.g., 5 seconds)
bash monitor_jobs.sh 5

# Single status check without looping
bash monitor_jobs.sh --once
```

---

## 🧩 Modular Pipeline Components

The pipeline is organized into modular scripts under `components/`:

| Step | Component | Main Script | Description |
| :---: | :--- | :--- | :--- |
| **01** | `01_fastp` | `run_fastp.sh` | FASTQ quality control, adapter trimming, and JSON report generation. |
| **02** | `02_star` | `run_star.sh` | STAR RNA alignment and splice/fusion detection. |
| **03** | `03_bwa_mem` | `run_bwa_mem.sh` | BWA-MEM2 DNA alignment, sorting, indexing, and duplicate marking. |
| **04** | `04_arriba` | `run_arriba.sh` | Arriba gene fusion calling from STAR BAM output. |
| **05** | `05_cnvkit` | `run_cnvkit.sh` | CNVkit copy number variation calling (`.cnr` & `.cns`). |
| **06** | `06_cnv_plots` | `run_cnv_plots.sh` | CNV visualization plot generation (`plot_cnv_from_ngs.py`). |
| **07** | `07_coverage` | `run_coverage.sh` | Target region depth coverage calculations & plotting (`coverage_plot.py`). |
| **08** | `08_variants` | `run_variants.sh` | Variant classification, population filtering, and OncoKB annotation (`ngs_variant_processor.py`). |
| **09** | `09_report` | `run_report.sh` | Aggregation into formatted Excel summary reports (`ngs_report.py`, `tsv_to_excel.py`). |
| **10** | `10_nonhuman_reads` | `run_nonhuman_reads.sh` | Extraction of non-human unmapped reads for metagenomic inspection. |

---

## 📂 Project Structure

```text
ngs-tumor-pipeline/
├── components/          # Modular step scripts (01_fastp through 10_nonhuman_reads)
├── config/              # Host configurations (common.sh, omen.sh, palma.sh)
├── lib/                 # Shared Bash functions (common_functions.sh)
├── resources/           # Reference bed files, panels, variant comments
├── input/               # Default input directory for FASTQ and VCF files
├── output/              # Default output directory for analysis results
├── monitor_jobs.sh      # Slurm job & progress monitoring dashboard (Palma)
├── ngs_tumor_pipeline.sh# Case-level orchestrator script
├── run.sh               # Main CLI launcher & Slurm batch orchestrator
├── setup.sh             # Environment setup & venv manager
└── .env                 # Local configuration & API tokens (OncoKB)
```

---

## 🆘 Troubleshooting & Support

* **Permission Denied**: Run scripts explicitly using `bash` (e.g., `bash setup.sh`).
* **Reference Path Not Found**: Ensure shared reference paths under `/cloud/wwu1/e_np_ngs/references/` are accessible by your HPC user group.
* **OncoKB Annotation Warnings**: Re-run `bash setup.sh` to update your `ONCOKB_API_TOKEN` if annotations are missing or skipped.
* **Questions / Issues**: Reach out anytime via the **Mattermost** channel! 😊👍