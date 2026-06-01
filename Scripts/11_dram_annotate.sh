#!/bin/bash
# =============================================================================
# Script : 11_dram_annotate.sh
# Purpose: Functionally annotate CheckM2-good MAGs using DRAM annotate.
#
# Input:
#   results/MAGs/<SAMPLE_ID>/good_MAGs_75_10/
#
# This folder is created by:
#   bash scripts/09_checkm2.sh <SAMPLE_ID>
#
# Previous step:
#   bash scripts/10_gtdbtk.sh <SAMPLE_ID>
#
# Output:
#   results/dram/<SAMPLE_ID>/annotation/
#   results/dram/<SAMPLE_ID>/annotation/annotations.tsv
#
# Usage:
#   bash scripts/11_dram_annotate.sh <SAMPLE_ID>
#
# Example:
#   bash scripts/11_dram_annotate.sh ERR12510647
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
    echo "Usage  : bash scripts/11_dram_annotate.sh <SAMPLE_ID>"
    echo "Example: bash scripts/11_dram_annotate.sh ERR12510647"
    echo ""
    exit 1
fi

SAMPLE=$1

echo ""
echo "======================================================"
echo "  Shotgun Metagenomics Pipeline — Step 11: DRAM Annotate"
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

COMPLETENESS=75
CONTAMINATION=10

GOOD_MAGS=$PROJECT/results/MAGs/$SAMPLE/good_MAGs_${COMPLETENESS}_${CONTAMINATION}

DRAM_OUT=$PROJECT/results/dram/$SAMPLE
ANNOTATION_OUT=$DRAM_OUT/annotation
INPUT_LIST=$DRAM_OUT/${SAMPLE}_dram_input_MAGs.txt

CHECKM2_GOOD_IDS=$PROJECT/results/checkm2/$SAMPLE/${SAMPLE}_good_MAG_IDs.txt
GTDBTK_SUMMARY=$PROJECT/results/gtdbtk/$SAMPLE/${SAMPLE}_GTDBTK_taxonomy_summary.tsv

LOGS=$PROJECT/logs
LOG=$LOGS/${SAMPLE}_11_dram_annotate.log

THREADS=16
MIN_CONTIG_SIZE=1000

# Your general database folder
DATABASE_ROOT=/mnt/e/Databases

mkdir -p "$DRAM_OUT" "$LOGS"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4 — LOG INITIALISATION
# ─────────────────────────────────────────────────────────────────────────────

{
    echo "============================================="
    echo " Script          : 11_dram_annotate.sh"
    echo " Sample          : $SAMPLE"
    echo " Started         : $(date '+%Y-%m-%d %H:%M:%S')"
    echo " Tool            : DRAM.py annotate"
    echo " Project         : $PROJECT"
    echo " Good MAG input  : $GOOD_MAGS"
    echo " CheckM2 good IDs: $CHECKM2_GOOD_IDS"
    echo " GTDB-Tk summary : $GTDBTK_SUMMARY"
    echo " DRAM output     : $ANNOTATION_OUT"
    echo " Database root   : $DATABASE_ROOT"
    echo " Conda env       : $CONDA_ENV"
    echo " Threads         : $THREADS"
    echo " Min contig size : $MIN_CONTIG_SIZE"
    echo " MAG rule        : CheckM2 completeness >= $COMPLETENESS, contamination <= $CONTAMINATION"
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
    echo "" | tee -a "$LOG"
    echo "Activate/check your DRAM environment:" | tee -a "$LOG"
    echo "  conda activate $CONDA_ENV" | tee -a "$LOG"
    echo "  DRAM.py --help" | tee -a "$LOG"
    exit 1
fi

if ! conda run -n "$CONDA_ENV" which DRAM-setup.py &>/dev/null; then
    echo "[ERROR] DRAM-setup.py not found in conda environment: $CONDA_ENV" | tee -a "$LOG"
    echo "Your DRAM installation may be incomplete." | tee -a "$LOG"
    exit 1
fi

DRAM_VERSION=$(conda run -n "$CONDA_ENV" DRAM.py --version 2>&1 | head -n1 || true)
log "DRAM found: $DRAM_VERSION"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 6 — INPUT CHECKS
# ─────────────────────────────────────────────────────────────────────────────

log "Checking CheckM2-good MAG input folder"

if [ ! -d "$GOOD_MAGS" ]; then
    echo "[ERROR] Good MAG folder not found:" | tee -a "$LOG"
    echo "        $GOOD_MAGS" | tee -a "$LOG"
    echo "" | tee -a "$LOG"
    echo "Run CheckM2 first:" | tee -a "$LOG"
    echo "        bash scripts/09_checkm2.sh $SAMPLE" | tee -a "$LOG"
    exit 1
fi

if find "$GOOD_MAGS" -maxdepth 1 -name "*.fa" | grep -q .; then
    EXT="fa"
elif find "$GOOD_MAGS" -maxdepth 1 -name "*.fasta" | grep -q .; then
    EXT="fasta"
elif find "$GOOD_MAGS" -maxdepth 1 -name "*.fna" | grep -q .; then
    EXT="fna"
else
    echo "[ERROR] No MAG FASTA files found in:" | tee -a "$LOG"
    echo "        $GOOD_MAGS" | tee -a "$LOG"
    echo "Expected files ending in .fa, .fasta, or .fna" | tee -a "$LOG"
    exit 1
fi

MAG_COUNT=$(find "$GOOD_MAGS" -maxdepth 1 -name "*.${EXT}" | wc -l)

if [ "$MAG_COUNT" -lt 1 ]; then
    echo "[ERROR] No good MAGs found in: $GOOD_MAGS" | tee -a "$LOG"
    exit 1
fi

log "Good MAG folder : $GOOD_MAGS"
log "MAG extension   : .$EXT"
log "Good MAG count  : $MAG_COUNT"

find "$GOOD_MAGS" -maxdepth 1 -name "*.${EXT}" | sort > "$INPUT_LIST"
log "DRAM input MAG list: $INPUT_LIST"

if [ -s "$CHECKM2_GOOD_IDS" ]; then
    GOOD_ID_COUNT=$(grep -v '^[[:space:]]*$' "$CHECKM2_GOOD_IDS" | wc -l)
    log "CheckM2 good MAG ID count: $GOOD_ID_COUNT"

    if [ "$GOOD_ID_COUNT" -ne "$MAG_COUNT" ]; then
        log "[WARN] CheckM2 good ID count and DRAM FASTA count differ"
        log "       Good IDs : $GOOD_ID_COUNT"
        log "       FASTAs   : $MAG_COUNT"
    fi
else
    log "[WARN] CheckM2 good MAG ID file not found or empty:"
    log "       $CHECKM2_GOOD_IDS"
fi

if [ ! -s "$GTDBTK_SUMMARY" ]; then
    log "[WARN] GTDB-Tk taxonomy summary not found:"
    log "       $GTDBTK_SUMMARY"
    log "       DRAM can still run, but final MAG taxonomy linking will need GTDB-Tk output."
else
    log "GTDB-Tk taxonomy summary found: $GTDBTK_SUMMARY"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 7 — DRAM DATABASE CONFIG CHECK
# ─────────────────────────────────────────────────────────────────────────────

log "Checking DRAM database configuration"

set +e

conda run -n "$CONDA_ENV" DRAM-setup.py print_config \
    2>&1 | tee -a "$LOG"

CONFIG_EXIT=${PIPESTATUS[0]}

set -e

if [ "$CONFIG_EXIT" -ne 0 ]; then
    echo "[ERROR] DRAM database config check failed." | tee -a "$LOG"
    echo "Run/check:" | tee -a "$LOG"
    echo "  conda activate $CONDA_ENV" | tee -a "$LOG"
    echo "  DRAM-setup.py print_config" | tee -a "$LOG"
    exit 1
fi

log "DRAM config printed successfully"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 8 — RESUME LOGIC
# ─────────────────────────────────────────────────────────────────────────────

ANNOTATIONS=$ANNOTATION_OUT/annotations.tsv

if [ -s "$ANNOTATIONS" ]; then
    echo ""
    echo "[SKIP] DRAM annotation already complete for sample: $SAMPLE"
    echo "       Annotation file: $ANNOTATIONS"
    echo "       Delete this folder to force rerun:"
    echo "       $ANNOTATION_OUT"
    echo ""
    exit 0
fi

if [ -d "$ANNOTATION_OUT" ] && [ ! -s "$ANNOTATIONS" ]; then
    log "Incomplete DRAM annotation output found. Removing:"
    log "$ANNOTATION_OUT"
    rm -rf "$ANNOTATION_OUT"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 9 — RUN DRAM ANNOTATE
# ─────────────────────────────────────────────────────────────────────────────

log "STEP 1/2 — Running DRAM.py annotate on CheckM2-good MAGs"
log "Input : $GOOD_MAGS"
log "Output: $ANNOTATION_OUT"

set +e

conda run -n "$CONDA_ENV" DRAM.py annotate \
    -i "$GOOD_MAGS"/*.${EXT} \
    -o "$ANNOTATION_OUT" \
    --threads "$THREADS" \
    --min_contig_size "$MIN_CONTIG_SIZE" \
    2>&1 | tee -a "$LOG"

DRAM_EXIT=${PIPESTATUS[0]}

set -e

if [ "$DRAM_EXIT" -ne 0 ]; then
    echo "[ERROR] DRAM annotation failed for sample: $SAMPLE" | tee -a "$LOG"
    echo "Check log: $LOG" | tee -a "$LOG"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 10 — OUTPUT VALIDATION
# ─────────────────────────────────────────────────────────────────────────────

log "STEP 2/2 — Validating DRAM annotation outputs"

if [ ! -s "$ANNOTATIONS" ]; then
    echo "[ERROR] DRAM finished, but annotations.tsv is missing or empty:" | tee -a "$LOG"
    echo "        $ANNOTATIONS" | tee -a "$LOG"
    exit 1
fi

ANNOTATION_LINES=$(wc -l < "$ANNOTATIONS")
log "DRAM annotations file: $ANNOTATIONS"
log "annotations.tsv lines: $ANNOTATION_LINES"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 11 — COMPLETION SUMMARY
# ─────────────────────────────────────────────────────────────────────────────

{
    echo "============================================="
    echo " Finished: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================="
} >> "$LOG"

echo ""
echo "======================================================"
echo "  Step 11 COMPLETE — $SAMPLE"
echo "======================================================"
echo "  Good MAG input folder : $GOOD_MAGS"
echo "  MAGs submitted        : $MAG_COUNT"
echo "  DRAM annotation output: $ANNOTATION_OUT"
echo "  Main annotation file  : $ANNOTATIONS"
echo "  Annotation lines      : $ANNOTATION_LINES"
echo "  Input MAG list        : $INPUT_LIST"
echo "  Log file              : $LOG"
echo ""
echo "  This file is used for MAG-level functional annotation:"
echo "  $ANNOTATIONS"
echo ""
echo "  Next step:"
echo "  bash scripts/12_dram_distill.sh $SAMPLE"
echo "======================================================"