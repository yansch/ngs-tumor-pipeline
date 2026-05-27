# 🧬 NGS Tumor Pipeline

This repository contains an automated pipeline for NGS tumor analysis, optimized for the **Palma** and **Omen** clusters. This guide is designed to help you get started even if you have never used Git or SSH keys before.

---

## 🔑 Step 1: Create a GitLab Access Token

Since we are not using SSH keys, you will need a **Personal Access Token (PAT)** to identify yourself to GitLab from the cluster.

1. Log in to your **GitLab** account.
2. Click on your **Profile Icon** (top right corner) and select **Preferences**.
3. On the left-hand sidebar, click **Access Tokens**.
4. Click **Add new token**.
5. Fill in the following:
* **Token name:** `HPC-Access`
* **Expiration date:** (Optional, leave blank for no expiry)
* **Select scopes:** Check only `read_repository`.


6. Click **Create personal access token**.
7. **⚠️ IMPORTANT:** Copy the token now. You will not be able to see it again.

---

## 📥 Step 2: Clone the Repository

Go to your terminal on the HPC and run the following command.

**Note:** Replace `<YOUR-TOKEN>` with the token you just copied, and ensure the URL matches your specific GitLab project path.

```bash
git clone https://oauth2:<YOUR-TOKEN>@gitlab.com/your-username/ngs-tumor-pipeline.git
cd ngs-tumor-pipeline

```

---

## 🛠️ Step 3: Installation & Setup

Run the automated setup script. This will detect which cluster you are on, load the necessary software modules, and create a private "Virtual Environment" in your scratch space so the pipeline has everything it needs to run.

```bash
bash setup.sh

```

---

## 🧪 Step 4: Running the Pipeline

### 1. Prepare your Data

The setup script created an input folder for you in your scratch directory. Move your FASTQ files there:

```bash
# Example for Palma
cp /path/to/your/files/*.fastq.gz /scratch/tmp/$USER/ngs-tumor-pipeline/input/fastq/

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

---

## 📂 Project Structure & Paths

* **Scripts:** Stored in your home directory (where you cloned the repo).
* **Environment:** Stored in `/scratch/tmp/$USER/ngs-tumor-pipeline/env`.
* **Outputs:** Results will be generated in `/scratch/tmp/$USER/ngs-tumor-pipeline/output`.

## 🆘 Troubleshooting

* **Permission Denied:** Ensure you are running the scripts with `bash` (e.g., `bash setup.sh`).
* **Token Expired:** If `git pull` or `git clone` stops working, repeat **Step 1** to generate a new token.
* **Missing References:** This pipeline relies on shared references. If you get an error regarding "Reference path not found," please contact the lab administrator to ensure the reference folders are shared with your user ID.