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

**Optional: Skip File Transfer Check**
By default, `run.sh` checks if a file transfer into the input folder is running (for about 5 seconds. If it is, run.sh waits for 5 minutes and then checks again. This prevents starting jobs that have incomplete data). Pass `--now` to skip the check:

```bash
bash run.sh --now
```

**Optional: Timelogging**
By using this command, each step will be time-logged. This is useful for delevopment (for example for calculating the factor thats used for calculating the estimated duration):

```bash
bash run.sh --timelog
```

---

## 📂 Project Structure & Paths

* **Inputs:** Put FASTQ and VCF files into the subfolder `input`.
* **Outputs:** Results will be generated in the subfolder `output`.
* Scripts and dependencies are stored in the directories `scripts` and `env`, respectively.

## 🆘 Troubleshooting

* **Permission Denied:** Ensure you are running the scripts with `bash` (e.g., `bash setup.sh`).
* **Missing References:** This pipeline relies on shared references. If you get an error regarding "Reference path not found," please contact via the Mattermost channel to ensure the reference folders are shared with your user.