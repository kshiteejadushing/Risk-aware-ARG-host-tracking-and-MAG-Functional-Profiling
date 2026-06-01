#!/bin/bash
# =============================================================================
# Script : 12_dram_distill.sh
# Purpose: Summarize DRAM annotations into genome-level metabolic summaries.
#
# Input:
#   results/dram/<SAMPLE_ID>/annotation/annotations.tsv
#
# This file is created by:
#   bash scripts/11_dram_annotate.sh <SAMPLE_ID>
#
# Output:
#   results/dram/<SAMPLE_ID>/distill/
#
# Usage:
#   bash scripts/12_dram_distill.sh <SAMPLE_ID>
#
# Example:
#   bash scripts/12_dram_distill.sh ERR12510647
#
# Author : Kshiteeja
# Project: Shotgun Metagenomics — ARG detection, MAG binning, host taxonomy,
#          pathway annotation, and bioremediation potential
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1 — ARGUMENT CHECK
# ─────────────────────────────────────────────────────────────────────────────

if [ $# -lt 1 ]; then
    echo ""
    echo "[ERROR] No sample ID provided."
    echo "Usage  : bash scripts/12_dram_distill.sh <SAMPLE_ID>"
    echo "Example: bash scripts/12_dram_distill.sh ERR12510647"
    echo ""
    exit 1
fi

SAMPLE=$1

echo ""
echo "======================================================"
echo "  Shotgun Metagenomics Pipeline — Step 12: DRAM Distill"
echo "  Sample : $SAMPLE"
echo "  Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "======================================================"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 — CONDA SETUP
# ─────────────────────────────────────────────────────────────────────────────

source /home/scccs1/miniconda3/etc/profile.d/conda.sh

CONDA_ENV="dram_env"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 — PATH DEFINITIONS
# ─────────────────────────────────────────────────────────────────────────────

PROJECT=/mnt/e/kshiteeja/shotgun_project

DRAM_OUT=$PROJECT/results/dram/$SAMPLE
ANNOTATION_OUT=$DRAM_OUT/annotation
DISTILL_OUT=$DRAM_OUT/distill

ANNOTATIONS=$ANNOTATION_OUT/annotations.tsv

LOGS=$PROJECT/logs
LOG=$LOGS/${SAMPLE}_12_dram_distill.log

mkdir -p "$DRAM_OUT" "$LOGS"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4 — LOG INITIALISATION
# ─────────────────────────────────────────────────────────────────────────────

{
    echo "============================================="
    echo " Script          : 12_dram_distill.sh"
    echo " Sample          : $SAMPLE"
    echo " Started         : $(date '+%Y-%m-%d %H:%M:%S')"
    echo " Tool            : DRAM.py distill"
    echo " Project         : $PROJECT"
    echo " Annotation input: $ANNOTATIONS"
    echo " Distill output  : $DISTILL_OUT"
    echo " Conda env       : $CONDA_ENV"
    echo "============================================="
} > "$LOG"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 5 — DEPENDENCY CHECK
# ─────────────────────────────────────────────────────────────────────────────

log "Checking DRAM installation in conda environment: $CONDA_ENV"

if ! conda run -n "$CONDA_ENV" which DRAM.py &>/dev/null; then
    echo "[ERROR] DRAM.py not found in conda environment: $CONDA_ENV" | tee -a "$LOG"
    echo "Check your DRAM environment:" | tee -a "$LOG"
    echo "  conda activate $CONDA_ENV" | tee -a "$LOG"
    echo "  DRAM.py --help" | tee -a "$LOG"
    exit 1
fi

DRAM_VERSION=$(conda run -n "$CONDA_ENV" DRAM.py --version 2>&1 | head -n1 || true)
log "DRAM found: $DRAM_VERSION"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 6 — INPUT CHECKS
# ─────────────────────────────────────────────────────────────────────────────

log "Checking DRAM annotation input"

if [ ! -s "$ANNOTATIONS" ]; then
    echo "[ERROR] DRAM annotations.tsv not found or empty:" | tee -a "$LOG"
    echo "        $ANNOTATIONS" | tee -a "$LOG"
    echo "" | tee -a "$LOG"
    echo "Run DRAM annotate first:" | tee -a "$LOG"
    echo "        bash scripts/11_dram_annotate.sh $SAMPLE" | tee -a "$LOG"
    exit 1
fi

ANNOTATION_LINES=$(wc -l < "$ANNOTATIONS")
log "Annotation file found: $ANNOTATIONS"
log "annotations.tsv lines: $ANNOTATION_LINES"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 7 — RESUME LOGIC
# ─────────────────────────────────────────────────────────────────────────────

if [ -d "$DISTILL_OUT" ] && find "$DISTILL_OUT" -type f | grep -q .; then
    echo ""
    echo "[SKIP] DRAM distill output already exists for sample: $SAMPLE"
    echo "       Distill folder: $DISTILL_OUT"
    echo "       Delete this folder to force rerun."
    echo ""
    exit 0
fi

if [ -d "$DISTILL_OUT" ]; then
    log "Empty/incomplete DRAM distill folder found. Removing:"
    log "$DISTILL_OUT"
    rm -rf "$DISTILL_OUT"
fi

mkdir -p "$DISTILL_OUT"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 8 — RUN DRAM DISTILL
# ─────────────────────────────────────────────────────────────────────────────

log "STEP 1/2 — Running DRAM.py distill"
log "Input : $ANNOTATIONS"
log "Output: $DISTILL_OUT"

set +e

conda run -n "$CONDA_ENV" DRAM.py distill \
    -i "$ANNOTATIONS" \
    -o "$DISTILL_OUT" \
    2>&1 | tee -a "$LOG"

DISTILL_EXIT=${PIPESTATUS[0]}

set -e

if [ "$DISTILL_EXIT" -ne 0 ]; then
    echo "[ERROR] DRAM distill failed for sample: $SAMPLE" | tee -a "$LOG"
    echo "Check log: $LOG" | tee -a "$LOG"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 9 — OUTPUT VALIDATION
# ─────────────────────────────────────────────────────────────────────────────

log "STEP 2/2 — Validating DRAM distill outputs"

DISTILL_FILE_COUNT=$(find "$DISTILL_OUT" -type f | wc -l)

if [ "$DISTILL_FILE_COUNT" -lt 1 ]; then
    echo "[ERROR] DRAM distill finished, but no output files were produced:" | tee -a "$LOG"
    echo "        $DISTILL_OUT" | tee -a "$LOG"
    exit 1
fi

log "DRAM distill output folder: $DISTILL_OUT"
log "Number of distill output files: $DISTILL_FILE_COUNT"

log "DRAM distill output files:"
find "$DISTILL_OUT" -maxdepth 2 -type f | sort | tee -a "$LOG"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 10 — COMPLETION SUMMARY
# ─────────────────────────────────────────────────────────────────────────────

{
    echo "============================================="
    echo " Finished: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================="
} >> "$LOG"

echo ""
echo "======================================================"
echo "  Step 12 COMPLETE — $SAMPLE"
echo "======================================================"
echo "  Annotation input : $ANNOTATIONS"
echo "  Annotation lines : $ANNOTATION_LINES"
echo "  Distill output   : $DISTILL_OUT"
echo "  Output file count: $DISTILL_FILE_COUNT"
echo "  Log file         : $LOG"
echo ""
echo "  DRAM distill summarizes MAG-level metabolism/pathway potential."
echo "  Use this with GTDB-Tk taxonomy and CheckM2 quality for final tables."
echo ""
echo "  Next step:"
echo "  Build final tables:"
echo "  13_table1_ARG_contig_bin.sh / .py"
echo "  14_table2_MAG_pathway_annotation.py"
echo "  15_table3_MAG_risk_bioremediation_score.py"
echo "======================================================"