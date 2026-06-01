#!/bin/bash
# =============================================================================
# Script : 01_read_qc.sh
# Purpose: Adapter trimming, quality filtering, and QC reporting of raw reads
#          for shotgun metagenomics (environmental/sewage samples)
# Usage  : bash scripts/01_read_qc.sh <SAMPLE_ID>
# Example: bash scripts/01_read_qc.sh ERR12510647
# Author : Kshiteeja
# Project: Shotgun Metagenomics — ARG detection, MAG binning, host taxonomy
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1 — ARGUMENT CHECK
# ─────────────────────────────────────────────────────────────────────────────
if [ $# -lt 1 ]; then
    echo ""
    echo "[ERROR] No sample ID provided."
    echo "Usage  : bash scripts/01_read_qc.sh <SAMPLE_ID>"
    echo "Example: bash scripts/01_read_qc.sh ERR12510647"
    echo ""
    exit 1
fi

SAMPLE=$1
echo ""
echo "=================================================="
echo "  Shotgun Metagenomics Pipeline — Step 01: QC"
echo "  Sample : $SAMPLE"
echo "  Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================="

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 — CONDA SETUP
# ─────────────────────────────────────────────────────────────────────────────
source /home/scccs1/miniconda3/etc/profile.d/conda.sh

CONDA_ENV="shotgun_qc"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 — DEPENDENCY CHECK
# ─────────────────────────────────────────────────────────────────────────────
echo "[CHECK] Verifying tools in conda environment: $CONDA_ENV"

for tool in fastp fastqc multiqc; do
    if ! conda run -n "$CONDA_ENV" which "$tool" &>/dev/null; then
        echo "[ERROR] '$tool' not found in conda environment '$CONDA_ENV'"
        echo "        Fix: conda install -n $CONDA_ENV -c bioconda $tool"
        exit 1
    else
        VERSION=$(conda run -n "$CONDA_ENV" "$tool" --version 2>&1 | head -n1)
        echo "[OK]    $tool — $VERSION"
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4 — PATH DEFINITIONS
# ─────────────────────────────────────────────────────────────────────────────
PROJECT=/mnt/e/kshiteeja/shotgun_project

RAW=$PROJECT/data/raw/$SAMPLE
CLEAN=$PROJECT/data/clean/$SAMPLE
QC=$PROJECT/results/qc/$SAMPLE
MULTIQC_OUT=$QC/multiqc
LOGS=$PROJECT/logs

mkdir -p "$CLEAN" "$QC" "$MULTIQC_OUT" "$LOGS"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 5 — INPUT FILE CHECK
# ─────────────────────────────────────────────────────────────────────────────
R1=$RAW/${SAMPLE}_1.fastq.gz
R2=$RAW/${SAMPLE}_2.fastq.gz

echo "[CHECK] Verifying input raw reads..."

if [ ! -f "$R1" ]; then
    echo "[ERROR] Missing R1 file: $R1"
    exit 1
fi

if [ ! -f "$R2" ]; then
    echo "[ERROR] Missing R2 file: $R2"
    exit 1
fi

R1_SIZE=$(du -sh "$R1" | cut -f1)
R2_SIZE=$(du -sh "$R2" | cut -f1)
echo "[OK]    R1 found: $R1 ($R1_SIZE)"
echo "[OK]    R2 found: $R2 ($R2_SIZE)"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 6 — OUTPUT FILE DEFINITIONS
# ─────────────────────────────────────────────────────────────────────────────
CLEAN_R1=$CLEAN/${SAMPLE}_1.clean.fastq.gz
CLEAN_R2=$CLEAN/${SAMPLE}_2.clean.fastq.gz
HTML=$QC/${SAMPLE}_fastp.html
JSON=$QC/${SAMPLE}_fastp.json
LOG=$LOGS/${SAMPLE}_01_read_qc.log

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 7 — THREAD SETTING
# ─────────────────────────────────────────────────────────────────────────────
# Adjust THREADS based on your machine. Check available cores with: nproc
THREADS=8

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 8 — RESUME LOGIC
# ─────────────────────────────────────────────────────────────────────────────
# If clean reads already exist and are non-empty, skip entirely
if [ -s "$CLEAN_R1" ] && [ -s "$CLEAN_R2" ]; then
    echo ""
    echo "[SKIP] Clean reads already exist for sample: $SAMPLE"
    echo "       $CLEAN_R1"
    echo "       $CLEAN_R2"
    echo "       Delete these files to force rerun."
    echo ""
    exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 9 — LOG FILE INITIALISATION
# ─────────────────────────────────────────────────────────────────────────────
{
    echo "============================================="
    echo " Script : 01_read_qc.sh"
    echo " Sample : $SAMPLE"
    echo " Started: $(date '+%Y-%m-%d %H:%M:%S')"
    echo " Threads: $THREADS"
    echo " R1     : $R1"
    echo " R2     : $R2"
    echo "============================================="
} > "$LOG"

# Helper logging function — prints to terminal AND appends to log file
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 10 — FASTP: ADAPTER TRIMMING + QUALITY FILTERING
# ─────────────────────────────────────────────────────────────────────────────
log "STEP 1/3 — fastp: adapter trimming and quality filtering"
log "Parameters: Q20, min_length=50, low_complexity_filter, PE correction"

conda run -n "$CONDA_ENV" fastp \
    -i  "$R1" \
    -I  "$R2" \
    -o  "$CLEAN_R1" \
    -O  "$CLEAN_R2" \
    -h  "$HTML" \
    -j  "$JSON" \
    --detect_adapter_for_pe \
    --qualified_quality_phred 30 \
    --unqualified_percent_limit 40 \
    --length_required 50 \
    --low_complexity_filter \
    --complexity_threshold 30 \
    --correction \
    --thread "$THREADS" \
    2>&1 | tee -a "$LOG"

# Check fastp exit code explicitly (tee masks it otherwise)
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo "[ERROR] fastp failed for sample: $SAMPLE"
    echo "        Check log: $LOG"
    exit 1
fi

# Sanity check — clean reads must be non-empty after fastp
if [ ! -s "$CLEAN_R1" ] || [ ! -s "$CLEAN_R2" ]; then
    echo "[ERROR] fastp produced empty output files for sample: $SAMPLE"
    echo "        This may indicate all reads were filtered out."
    echo "        Check: $JSON"
    exit 1
fi

log "fastp DONE — clean reads written to: $CLEAN"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 11 — FASTQC: POST-TRIMMING QUALITY REPORT
# ─────────────────────────────────────────────────────────────────────────────
log "STEP 2/3 — FastQC: quality report on clean reads"

conda run -n "$CONDA_ENV" fastqc \
    "$CLEAN_R1" "$CLEAN_R2" \
    --outdir "$QC" \
    --threads "$THREADS" \
    2>&1 | tee -a "$LOG"

if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo "[ERROR] FastQC failed for sample: $SAMPLE"
    echo "        Check log: $LOG"
    exit 1
fi

log "FastQC DONE — reports written to: $QC"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 12 — MULTIQC: AGGREGATE REPORT FOR THIS SAMPLE
# ─────────────────────────────────────────────────────────────────────────────
# NOTE: This generates a per-sample MultiQC report.
# At the end of the full project, run MultiQC across ALL samples together:
#   multiqc $PROJECT/results/qc/ -o $PROJECT/results/qc/multiqc_all_samples/
log "STEP 3/3 — MultiQC: aggregating QC reports"

conda run -n "$CONDA_ENV" multiqc \
    "$QC" \
    --outdir "$MULTIQC_OUT" \
    --filename "${SAMPLE}_multiqc_report" \
    --force \
    2>&1 | tee -a "$LOG"

if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo "[ERROR] MultiQC failed for sample: $SAMPLE"
    echo "        Check log: $LOG"
    exit 1
fi

log "MultiQC DONE — report written to: $MULTIQC_OUT"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 13 — COMPLETION SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
{
    echo "============================================="
    echo " Finished: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================="
} >> "$LOG"

echo ""
echo "=================================================="
echo "  Step 01 COMPLETE — $SAMPLE"
echo "=================================================="
echo "  Clean R1   : $CLEAN_R1"
echo "  Clean R2   : $CLEAN_R2"
echo "  fastp JSON : $JSON"
echo "  fastp HTML : $HTML"
echo "  FastQC dir : $QC"
echo "  MultiQC    : $MULTIQC_OUT/${SAMPLE}_multiqc_report.html"
echo "  Log file   : $LOG"
echo ""
echo "  Next step  : bash scripts/02_assembly.sh $SAMPLE"
echo "=================================================="