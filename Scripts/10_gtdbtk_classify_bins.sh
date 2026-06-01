#!/bin/bash
# =============================================================================
# Script : 10_gtdbtk.sh
# Purpose: Assign taxonomy to CheckM2-good MAGs using GTDB-Tk classify_wf.
#
# Input:
#   results/MAGs/<SAMPLE_ID>/good_MAGs_75_10/
#
# This folder is created by:
#   bash scripts/09_checkm2.sh <SAMPLE_ID>
#
# Output:
#   results/gtdbtk/<SAMPLE_ID>/classify/
#   results/gtdbtk/<SAMPLE_ID>/<SAMPLE_ID>_GTDBTK_taxonomy_summary.tsv
#
# Usage:
#   bash scripts/10_gtdbtk.sh <SAMPLE_ID>
#
# Example:
#   bash scripts/10_gtdbtk.sh ERR12510647
#
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
    echo "Usage  : bash scripts/10_gtdbtk.sh <SAMPLE_ID>"
    echo "Example: bash scripts/10_gtdbtk.sh ERR12510647"
    echo ""
    exit 1
fi

SAMPLE=$1

echo ""
echo "======================================================"
echo "  Shotgun Metagenomics Pipeline — Step 10: GTDB-Tk"
echo "  Sample : $SAMPLE"
echo "  Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "======================================================"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 — CONDA SETUP
# ─────────────────────────────────────────────────────────────────────────────

source /home/scccs1/miniconda3/etc/profile.d/conda.sh

CONDA_ENV="shotgun_gtdbtk"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 — PATH DEFINITIONS
# ─────────────────────────────────────────────────────────────────────────────

PROJECT=/mnt/e/kshiteeja/shotgun_project

COMPLETENESS=75
CONTAMINATION=10

GOOD_MAGS=$PROJECT/results/MAGs/$SAMPLE/good_MAGs_${COMPLETENESS}_${CONTAMINATION}

GTDBTK_OUT=$PROJECT/results/gtdbtk/$SAMPLE
OUTDIR=$GTDBTK_OUT/classify
COMBINED_SUMMARY=$GTDBTK_OUT/${SAMPLE}_GTDBTK_taxonomy_summary.tsv
SUBMITTED_LIST=$GTDBTK_OUT/${SAMPLE}_gtdbtk_submitted_MAGs.txt

CHECKM2_GOOD_IDS=$PROJECT/results/checkm2/$SAMPLE/${SAMPLE}_good_MAG_IDs.txt

LOGS=$PROJECT/logs
LOG=$LOGS/${SAMPLE}_10_gtdbtk.log

# Your updated database location
export GTDBTK_DATA_PATH=/mnt/e/Databases/GTDBTK

THREADS=16

# pplacer is RAM-heavy. Keep this low to avoid WSL/server memory crashes.
PPLACER_CPUS=1

mkdir -p "$GTDBTK_OUT" "$OUTDIR" "$LOGS"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4 — LOG INITIALISATION
# ─────────────────────────────────────────────────────────────────────────────

{
    echo "============================================="
    echo " Script          : 10_gtdbtk.sh"
    echo " Sample          : $SAMPLE"
    echo " Started         : $(date '+%Y-%m-%d %H:%M:%S')"
    echo " Tool            : GTDB-Tk classify_wf"
    echo " Project         : $PROJECT"
    echo " Good MAG input  : $GOOD_MAGS"
    echo " CheckM2 good IDs: $CHECKM2_GOOD_IDS"
    echo " GTDB-Tk output  : $OUTDIR"
    echo " Combined summary: $COMBINED_SUMMARY"
    echo " GTDBTK DB       : $GTDBTK_DATA_PATH"
    echo " Conda env       : $CONDA_ENV"
    echo " Threads         : $THREADS"
    echo " pplacer CPUs    : $PPLACER_CPUS"
    echo " MAG rule        : CheckM2 completeness >= $COMPLETENESS, contamination <= $CONTAMINATION"
    echo "============================================="
} > "$LOG"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 5 — DEPENDENCY CHECK
# ─────────────────────────────────────────────────────────────────────────────

log "Checking GTDB-Tk installation in conda environment: $CONDA_ENV"

if ! conda run -n "$CONDA_ENV" which gtdbtk &>/dev/null; then
    echo "[ERROR] gtdbtk not found in conda environment: $CONDA_ENV" | tee -a "$LOG"
    echo "" | tee -a "$LOG"
    echo "Install/check the environment, for example:" | tee -a "$LOG"
    echo "  conda install -n $CONDA_ENV -c conda-forge -c bioconda gtdbtk" | tee -a "$LOG"
    exit 1
fi

GTDBTK_VERSION=$(conda run -n "$CONDA_ENV" gtdbtk --version 2>&1 | head -n1 || true)
log "GTDB-Tk found: $GTDBTK_VERSION"

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

if [ -s "$CHECKM2_GOOD_IDS" ]; then
    GOOD_ID_COUNT=$(grep -v '^[[:space:]]*$' "$CHECKM2_GOOD_IDS" | wc -l)
    log "CheckM2 good MAG ID count: $GOOD_ID_COUNT"

    if [ "$GOOD_ID_COUNT" -ne "$MAG_COUNT" ]; then
        log "[WARN] CheckM2 good ID count and FASTA count differ"
        log "       Good IDs : $GOOD_ID_COUNT"
        log "       FASTAs   : $MAG_COUNT"
    fi
else
    log "[WARN] CheckM2 good MAG ID file not found or empty:"
    log "       $CHECKM2_GOOD_IDS"
fi

# Save submitted MAG list
find "$GOOD_MAGS" -maxdepth 1 -name "*.${EXT}" -printf "%f\n" | sort > "$SUBMITTED_LIST"
log "Submitted MAG list: $SUBMITTED_LIST"

# Verify GTDB-Tk database
log "Checking GTDB-Tk database path"

if [ ! -d "$GTDBTK_DATA_PATH" ]; then
    echo "[ERROR] GTDB-Tk database folder not found:" | tee -a "$LOG"
    echo "        $GTDBTK_DATA_PATH" | tee -a "$LOG"
    echo "Edit GTDBTK_DATA_PATH in this script." | tee -a "$LOG"
    exit 1
fi

DB_SIZE=$(du -sh "$GTDBTK_DATA_PATH" 2>/dev/null | cut -f1 || echo "unknown")
log "GTDB-Tk database: $GTDBTK_DATA_PATH ($DB_SIZE)"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 7 — RESUME LOGIC
# ─────────────────────────────────────────────────────────────────────────────

BAC_SUMMARY=$OUTDIR/gtdbtk.bac120.summary.tsv
AR_SUMMARY=$OUTDIR/gtdbtk.ar53.summary.tsv

if [ -s "$BAC_SUMMARY" ] || [ -s "$AR_SUMMARY" ]; then
    echo ""
    echo "[SKIP] GTDB-Tk classification already complete for sample: $SAMPLE"
    echo "       Bacterial summary: $BAC_SUMMARY"
    echo "       Archaeal summary : $AR_SUMMARY"
    echo "       Combined summary : $COMBINED_SUMMARY"
    echo "       Delete this folder to force rerun:"
    echo "       $OUTDIR"
    echo ""

    if [ ! -s "$COMBINED_SUMMARY" ]; then
        echo "[INFO] Combined summary missing — recreating..."
        if [ -s "$BAC_SUMMARY" ] && [ -s "$AR_SUMMARY" ]; then
            head -n1 "$BAC_SUMMARY" > "$COMBINED_SUMMARY"
            tail -n +2 "$BAC_SUMMARY" >> "$COMBINED_SUMMARY"
            tail -n +2 "$AR_SUMMARY" >> "$COMBINED_SUMMARY"
        elif [ -s "$BAC_SUMMARY" ]; then
            cp "$BAC_SUMMARY" "$COMBINED_SUMMARY"
        else
            cp "$AR_SUMMARY" "$COMBINED_SUMMARY"
        fi
        echo "[OK] Combined summary recreated: $COMBINED_SUMMARY"
    fi

    exit 0
fi

# Remove incomplete classify output from previous failed run
if [ -d "$OUTDIR" ]; then
    log "Cleaning incomplete GTDB-Tk output folder before rerun:"
    log "$OUTDIR"
    rm -rf "$OUTDIR"
    mkdir -p "$OUTDIR"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 8 — CHECK GTDB-TK INSTALLATION + DATABASE
# ─────────────────────────────────────────────────────────────────────────────

log "STEP 1/4 — Running GTDB-Tk check_install"

set +e

conda run -n "$CONDA_ENV" gtdbtk check_install \
    2>&1 | tee -a "$LOG"

CHECK_EXIT=${PIPESTATUS[0]}

set -e

if [ "$CHECK_EXIT" -ne 0 ]; then
    echo "[ERROR] GTDB-Tk check_install failed." | tee -a "$LOG"
    echo "Database may be incomplete or GTDBTK_DATA_PATH may be wrong." | tee -a "$LOG"
    echo "Database path: $GTDBTK_DATA_PATH" | tee -a "$LOG"
    echo "Check log: $LOG" | tee -a "$LOG"
    exit 1
fi

log "GTDB-Tk database check passed"

if [ "$MAG_COUNT" -gt 50 ]; then
    log "[WARN] Large good-MAG count: $MAG_COUNT"
    log "pplacer RAM usage scales with MAG count."
    log "Monitor memory during run:"
    log "  watch -n 5 free -h"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 9 — RUN GTDB-TK CLASSIFY_WF
# ─────────────────────────────────────────────────────────────────────────────

log "STEP 2/4 — Running GTDB-Tk classify_wf only on CheckM2-good MAGs"
log "Input : $GOOD_MAGS"
log "Output: $OUTDIR"

set +e

conda run -n "$CONDA_ENV" gtdbtk classify_wf \
    --genome_dir "$GOOD_MAGS" \
    --out_dir "$OUTDIR" \
    --extension "$EXT" \
    --cpus "$THREADS" \
    --pplacer_cpus "$PPLACER_CPUS" \
    2>&1 | tee -a "$LOG"

GTDBTK_EXIT=${PIPESTATUS[0]}

set -e

if [ "$GTDBTK_EXIT" -ne 0 ]; then
    echo "[ERROR] GTDB-Tk classify_wf failed for sample: $SAMPLE" | tee -a "$LOG"
    echo "Check log: $LOG" | tee -a "$LOG"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 10 — OUTPUT VALIDATION
# ─────────────────────────────────────────────────────────────────────────────

log "STEP 3/4 — Validating GTDB-Tk outputs"

if [ ! -s "$BAC_SUMMARY" ] && [ ! -s "$AR_SUMMARY" ]; then
    echo "[ERROR] No GTDB-Tk summary files produced." | tee -a "$LOG"
    echo "Expected one or both of:" | tee -a "$LOG"
    echo "  $BAC_SUMMARY" | tee -a "$LOG"
    echo "  $AR_SUMMARY" | tee -a "$LOG"
    exit 1
fi

BAC_COUNT=0
AR_COUNT=0

if [ -s "$BAC_SUMMARY" ]; then
    BAC_COUNT=$(tail -n +2 "$BAC_SUMMARY" | wc -l)
    log "Bacterial MAGs classified: $BAC_COUNT"
fi

if [ -s "$AR_SUMMARY" ]; then
    AR_COUNT=$(tail -n +2 "$AR_SUMMARY" | wc -l)
    log "Archaeal MAGs classified: $AR_COUNT"
fi

TOTAL_CLASSIFIED=$((BAC_COUNT + AR_COUNT))
log "Total MAGs classified: $TOTAL_CLASSIFIED"

if [ "$TOTAL_CLASSIFIED" -eq 0 ]; then
    log "[WARN] Zero MAGs were classified by GTDB-Tk"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 11 — CREATE COMBINED TAXONOMY SUMMARY
# ─────────────────────────────────────────────────────────────────────────────

log "STEP 4/4 — Creating combined MAG taxonomy summary"

if [ -s "$BAC_SUMMARY" ] && [ -s "$AR_SUMMARY" ]; then
    head -n1 "$BAC_SUMMARY" > "$COMBINED_SUMMARY"
    tail -n +2 "$BAC_SUMMARY" >> "$COMBINED_SUMMARY"
    tail -n +2 "$AR_SUMMARY" >> "$COMBINED_SUMMARY"
elif [ -s "$BAC_SUMMARY" ]; then
    cp "$BAC_SUMMARY" "$COMBINED_SUMMARY"
else
    cp "$AR_SUMMARY" "$COMBINED_SUMMARY"
fi

if [ ! -s "$COMBINED_SUMMARY" ]; then
    echo "[ERROR] Failed to create combined taxonomy summary." | tee -a "$LOG"
    exit 1
fi

log "Combined taxonomy summary: $COMBINED_SUMMARY"
log "First 5 taxonomy records:"
head -n 6 "$COMBINED_SUMMARY" | tee -a "$LOG"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 12 — COMPLETION SUMMARY
# ─────────────────────────────────────────────────────────────────────────────

{
    echo "============================================="
    echo " Finished: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================="
} >> "$LOG"

echo ""
echo "======================================================"
echo "  Step 10 COMPLETE — $SAMPLE"
echo "======================================================"
echo "  Good MAG input folder : $GOOD_MAGS"
echo "  Good MAGs submitted   : $MAG_COUNT"
echo "  MAGs classified       : $TOTAL_CLASSIFIED"
echo "  Bacterial MAGs        : $BAC_COUNT"
echo "  Archaeal MAGs         : $AR_COUNT"
echo ""
echo "  Output files:"
echo "  GTDB-Tk output        : $OUTDIR"
echo "  Combined taxonomy     : $COMBINED_SUMMARY"
echo "  Submitted MAG list    : $SUBMITTED_LIST"
echo "  Log file              : $LOG"
echo ""
echo "  Key columns in combined summary:"
echo "  Col 1 : user_genome    → MAG/bin ID"
echo "  Col 2 : classification → full GTDB taxonomy string"
echo ""
echo "  Next step:"
echo "  bash scripts/11_dram_annotate.sh $SAMPLE"
echo "======================================================"