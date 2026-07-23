# 🧬 NGS Tumor Pipeline

This repository contains an automated pipeline for NGS tumor analysis, optimized for PALMA II and Omen. Please read the installation instructions carefully! 😊👍 If you have questions, feel free to reach out via the Mattermost channel anytime.

---

## 📥 Step 1: Clone the Repository

Go to your terminal on the HPC and run the following command to clone the repository into your scratch folder.

```bash
cd /scratch/tmp/$USER
git clone https://github.com/yansch/ngs-tumor-pipeline.git
cd ngs-tumor-pipeline
```

---

## 🛠️ Step 2: Installation & Setup

Run the automated setup script. This will detect which cluster you are on, load the necessary software modules, and create a private "Virtual Environment" in your scratch space so the pipeline has everything it needs to run.

```bash
bash setup.sh
```

During setup, you will be prompted for an optional OncoKB API token. Paste it and press Enter to save it, or just press Enter to keep the current token or skip for now. You can re-run the setup at any time to update it.

---

## 🧪 Step 3: Running the Pipeline

### 1. Prepare your Data

The setup script created an input folder for you in your scratch directory. Move your FASTQ and VCF files there:

```bash
# Example for Palma
cp /path/to/your/files/*.fastq.gz /scratch/tmp/$USER/ngs-tumor-pipeline/input/
```

### 2. Launch the Analysis

Run the orchestrator script. It will scan your input folder and automatically submit jobs to the cluster.

```bash
bash run.sh
```

**Optional: Dry Run**
To see what the pipeline *would* do without actually starting any jobs, use:

```bash
bash run.sh --dry-run
```

**Optional: Preserve Existing Outputs**
By default, `run.sh` clears the pipeline tmp and output directories before starting a new run. To keep previous results, pass:

```bash
bash run.sh --keep-existing
```

**Optional: Override Configuration Values**
You can override host config values at runtime:

```bash
# Scalar overrides from CLI (repeat --set as needed)
bash run.sh --set PIPELINE_THREADS=32 --set RESULTS_BASE=/scratch/tmp/$USER/ngs-output
```

```bash
# File-based overrides (recommended for arrays/modules)
bash run.sh --overrides-file /path/to/my-overrides.sh
```

Override precedence is:

1. Host defaults (`config/omen.sh` or `config/palma.sh`)
2. `.env` (if present in project root)
3. `--overrides-file`
4. `--set`

Use `bash run.sh --help` to see all options.

---

## 📂 Project Structure & Paths

* **Inputs:** Put FASTQ and VCF files into the subfolder `input`.
* **Outputs:** Results will be generated in the subfolder `output`.
* Scripts and dependencies are stored in the directories `scripts` and `env`, respectively.

## 🆘 Troubleshooting

* **Permission Denied:** Ensure you are running the scripts with `bash` (e.g., `bash setup.sh`).
* **Missing References:** This pipeline relies on shared references. If you get an error regarding "Reference path not found," please contact via the Mattermost channel to ensure the reference folders are shared with your user.