#!/bin/bash
# =============================================================================
# Script : 09_checkm2.sh
# Purpose: Assess quality of refined MAGs using CheckM2.
#          Produces completeness/contamination scores and creates the final
#          good-MAG FASTA folder for downstream GTDB-Tk and DRAM.
#
# Input:
#   results/bin_refinement/<SAMPLE_ID>/metawrap_75_10_bins/
#
# Main outputs:
#   results/checkm2/<SAMPLE_ID>/quality_report.tsv
#   results/checkm2/<SAMPLE_ID>/<SAMPLE_ID>_checkm2_all.tsv
#   results/checkm2/<SAMPLE_ID>/<SAMPLE_ID>_checkm2_good_MAGs.tsv
#   results/checkm2/<SAMPLE_ID>/<SAMPLE_ID>_good_MAG_IDs.txt
#   results/MAGs/<SAMPLE_ID>/good_MAGs_75_10/
#
# Good MAG threshold:
#   Completeness >= 75
#   Contamination <= 10
#
# Usage:
#   bash scripts/09_checkm2.sh <SAMPLE_ID>
#
# Example:
#   bash scripts/09_checkm2.sh ERR12510647
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
    echo "Usage  : bash scripts/09_checkm2.sh <SAMPLE_ID>"
    echo "Example: bash scripts/09_checkm2.sh ERR12510647"
    echo ""
    exit 1
fi

SAMPLE=$1

echo ""
echo "======================================================"
echo "  Shotgun Metagenomics Pipeline — Step 09: CheckM2"
echo "  Sample : $SAMPLE"
echo "  Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "======================================================"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 — CONDA SETUP
# ─────────────────────────────────────────────────────────────────────────────

source /home/scccs1/miniconda3/etc/profile.d/conda.sh

CONDA_ENV="checkm2_env"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 — PATH DEFINITIONS
# ─────────────────────────────────────────────────────────────────────────────

PROJECT=/mnt/e/kshiteeja/shotgun_project

# These thresholds must match Script 08 bin_refinement.
COMPLETENESS=75
CONTAMINATION=10

BINS=$PROJECT/results/bin_refinement/$SAMPLE/metawrap_${COMPLETENESS}_${CONTAMINATION}_bins

CHECKM2_OUT=$PROJECT/results/checkm2/$SAMPLE
MAGS_OUT=$PROJECT/results/MAGs/$SAMPLE
GOOD_MAG_FASTA_DIR=$MAGS_OUT/good_MAGs_${COMPLETENESS}_${CONTAMINATION}

LOGS=$PROJECT/logs

# Your updated database location
CHECKM2_DB_DIR=/mnt/e/Databases/CHECKM2

mkdir -p "$CHECKM2_OUT" "$MAGS_OUT" "$GOOD_MAG_FASTA_DIR" "$LOGS"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4 — OUTPUT FILE DEFINITIONS
# ─────────────────────────────────────────────────────────────────────────────

QUALITY_REPORT=$CHECKM2_OUT/quality_report.tsv

ALL_TABLE=$CHECKM2_OUT/${SAMPLE}_checkm2_all.tsv

GOOD_TABLE_75_10=$CHECKM2_OUT/${SAMPLE}_checkm2_good_MAGs_${COMPLETENESS}_${CONTAMINATION}.tsv
GOOD_IDS_75_10=$CHECKM2_OUT/${SAMPLE}_good_MAG_IDs_${COMPLETENESS}_${CONTAMINATION}.txt

# Generic filenames for downstream scripts
GOOD_TABLE=$CHECKM2_OUT/${SAMPLE}_checkm2_good_MAGs.tsv
GOOD_IDS=$CHECKM2_OUT/${SAMPLE}_good_MAG_IDs.txt

COPIED_FASTA_TABLE=$CHECKM2_OUT/${SAMPLE}_good_MAG_FASTA_paths.tsv
MISSING_FASTA_LIST=$CHECKM2_OUT/${SAMPLE}_missing_good_MAG_FASTAs.txt

LOG=$LOGS/${SAMPLE}_09_checkm2.log

THREADS=16

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 5 — LOG INITIALISATION
# ─────────────────────────────────────────────────────────────────────────────

{
    echo "============================================="
    echo " Script         : 09_checkm2.sh"
    echo " Sample         : $SAMPLE"
    echo " Started        : $(date '+%Y-%m-%d %H:%M:%S')"
    echo " Tool           : CheckM2 predict"
    echo " Project        : $PROJECT"
    echo " Input bins     : $BINS"
    echo " CheckM2 output : $CHECKM2_OUT"
    echo " Good MAG FASTA : $GOOD_MAG_FASTA_DIR"
    echo " DB folder      : $CHECKM2_DB_DIR"
    echo " Conda env      : $CONDA_ENV"
    echo " Threads        : $THREADS"
    echo " Good MAG rule  : completeness >= $COMPLETENESS, contamination <= $CONTAMINATION"
    echo "============================================="
} > "$LOG"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 6 — DEPENDENCY CHECK
# ─────────────────────────────────────────────────────────────────────────────

log "Checking CheckM2 installation in conda environment: $CONDA_ENV"

if ! conda run -n "$CONDA_ENV" which checkm2 &>/dev/null; then
    echo "[ERROR] checkm2 not found in conda environment: $CONDA_ENV" | tee -a "$LOG"
    echo "" | tee -a "$LOG"
    echo "Fix option 1:" | tee -a "$LOG"
    echo "  conda create -n checkm2_env -c conda-forge -c bioconda checkm2 -y" | tee -a "$LOG"
    echo "" | tee -a "$LOG"
    echo "Fix option 2, if your env has another name:" | tee -a "$LOG"
    echo "  edit CONDA_ENV in this script" | tee -a "$LOG"
    exit 1
fi

CHECKM2_VERSION=$(conda run -n "$CONDA_ENV" checkm2 --version 2>&1 | head -n1 || true)
log "CheckM2 found: $CHECKM2_VERSION"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 7 — INPUT BIN CHECKS
# ─────────────────────────────────────────────────────────────────────────────

log "Checking refined MAG input folder"

if [ ! -d "$BINS" ]; then
    echo "[ERROR] Refined bins folder not found:" | tee -a "$LOG"
    echo "        $BINS" | tee -a "$LOG"
    echo "" | tee -a "$LOG"
    echo "Run bin refinement first:" | tee -a "$LOG"
    echo "        bash scripts/08_bin_refinement.sh $SAMPLE" | tee -a "$LOG"
    echo "" | tee -a "$LOG"
    echo "This script expects:" | tee -a "$LOG"
    echo "        metawrap_${COMPLETENESS}_${CONTAMINATION}_bins" | tee -a "$LOG"
    exit 1
fi

# Auto-detect bin FASTA extension
if find "$BINS" -maxdepth 1 -name "*.fa" | grep -q .; then
    EXT="fa"
elif find "$BINS" -maxdepth 1 -name "*.fasta" | grep -q .; then
    EXT="fasta"
elif find "$BINS" -maxdepth 1 -name "*.fna" | grep -q .; then
    EXT="fna"
else
    echo "[ERROR] No bin FASTA files found in:" | tee -a "$LOG"
    echo "        $BINS" | tee -a "$LOG"
    echo "Expected files ending in .fa, .fasta, or .fna" | tee -a "$LOG"
    exit 1
fi

BIN_COUNT=$(find "$BINS" -maxdepth 1 -name "*.${EXT}" | wc -l)

if [ "$BIN_COUNT" -lt 1 ]; then
    echo "[ERROR] No bins found in: $BINS" | tee -a "$LOG"
    exit 1
fi

log "Bins folder : $BINS"
log "Extension   : .$EXT"
log "Bin count   : $BIN_COUNT"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 8 — CHECKM2 DATABASE CHECK
# ─────────────────────────────────────────────────────────────────────────────

log "Checking CheckM2 database"

if [ ! -d "$CHECKM2_DB_DIR" ]; then
    echo "[ERROR] CheckM2 database folder not found:" | tee -a "$LOG"
    echo "        $CHECKM2_DB_DIR" | tee -a "$LOG"
    echo "" | tee -a "$LOG"
    echo "Download it using:" | tee -a "$LOG"
    echo "  mkdir -p $CHECKM2_DB_DIR" | tee -a "$LOG"
    echo "  conda activate $CONDA_ENV" | tee -a "$LOG"
    echo "  checkm2 database --download --path $CHECKM2_DB_DIR --no_write_json_db" | tee -a "$LOG"
    exit 1
fi

CHECKM2_DB=$(find "$CHECKM2_DB_DIR" -type f -name "*.dmnd" | head -n1 || true)

if [ -z "$CHECKM2_DB" ]; then
    echo "[ERROR] No .dmnd database file found in:" | tee -a "$LOG"
    echo "        $CHECKM2_DB_DIR" | tee -a "$LOG"
    echo "" | tee -a "$LOG"
    echo "Your CheckM2 database may be incomplete." | tee -a "$LOG"
    echo "Download it using:" | tee -a "$LOG"
    echo "  conda activate $CONDA_ENV" | tee -a "$LOG"
    echo "  checkm2 database --download --path $CHECKM2_DB_DIR --no_write_json_db" | tee -a "$LOG"
    exit 1
fi

DB_SIZE=$(du -sh "$CHECKM2_DB" | cut -f1 || echo "unknown")
log "CheckM2 database file: $CHECKM2_DB"
log "Database size: $DB_SIZE"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 9 — RESUME LOGIC
# ─────────────────────────────────────────────────────────────────────────────

RUN_CHECKM2=true

if [ -s "$QUALITY_REPORT" ] && [ -s "$GOOD_TABLE" ] && [ -s "$GOOD_IDS" ] && [ -d "$GOOD_MAG_FASTA_DIR" ]; then
    GOOD_FASTA_COUNT=$(find "$GOOD_MAG_FASTA_DIR" -maxdepth 1 -name "*.fa" | wc -l)

    if [ "$GOOD_FASTA_COUNT" -gt 0 ]; then
        echo ""
        echo "[SKIP] CheckM2 and good-MAG FASTA preparation already complete for sample: $SAMPLE"
        echo "       Quality report : $QUALITY_REPORT"
        echo "       Good MAG table : $GOOD_TABLE"
        echo "       Good MAG IDs   : $GOOD_IDS"
        echo "       Good MAG FASTA : $GOOD_MAG_FASTA_DIR"
        echo "       FASTA count    : $GOOD_FASTA_COUNT"
        echo ""
        exit 0
    fi
fi

if [ -s "$QUALITY_REPORT" ]; then
    log "Existing quality_report.tsv found"
    log "Skipping CheckM2 run and regenerating 75/10 tables + good MAG FASTA folder"
    RUN_CHECKM2=false
fi

if [ "$RUN_CHECKM2" = true ]; then
    if [ -d "$CHECKM2_OUT" ] && [ ! -s "$QUALITY_REPORT" ]; then
        log "Incomplete CheckM2 output folder found. Cleaning it before rerun:"
        log "$CHECKM2_OUT"
        rm -rf "$CHECKM2_OUT"
        mkdir -p "$CHECKM2_OUT"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 10 — RUN CHECKM2
# ─────────────────────────────────────────────────────────────────────────────

if [ "$RUN_CHECKM2" = true ]; then
    log "STEP 1/4 — Running CheckM2 predict"
    log "Input  : $BINS"
    log "Output : $CHECKM2_OUT"
    log "DB     : $CHECKM2_DB"

    set +e

    conda run -n "$CONDA_ENV" checkm2 predict \
        --input "$BINS" \
        --output-directory "$CHECKM2_OUT" \
        --extension "$EXT" \
        --database_path "$CHECKM2_DB" \
        --threads "$THREADS" \
        --force \
        2>&1 | tee -a "$LOG"

    CHECKM2_EXIT=${PIPESTATUS[0]}

    set -e

    if [ "$CHECKM2_EXIT" -ne 0 ]; then
        echo "[ERROR] CheckM2 failed for sample: $SAMPLE" | tee -a "$LOG"
        echo "        Check log: $LOG" | tee -a "$LOG"
        exit 1
    fi
else
    log "STEP 1/4 — CheckM2 already run; using existing quality_report.tsv"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 11 — OUTPUT VALIDATION
# ─────────────────────────────────────────────────────────────────────────────

log "STEP 2/4 — Validating CheckM2 outputs"

if [ ! -s "$QUALITY_REPORT" ]; then
    echo "[ERROR] CheckM2 quality report missing or empty:" | tee -a "$LOG"
    echo "        $QUALITY_REPORT" | tee -a "$LOG"
    exit 1
fi

TOTAL_MAGS=$(tail -n +2 "$QUALITY_REPORT" | wc -l)
log "Total MAGs assessed: $TOTAL_MAGS"

# CheckM2 quality_report.tsv normally has:
# Col 1 = Name
# Col 2 = Completeness
# Col 3 = Contamination

HIGH_QUALITY=$(tail -n +2 "$QUALITY_REPORT" | awk -F'\t' '$2>=90 && $3<=5' | wc -l)
GOOD_QUALITY=$(tail -n +2 "$QUALITY_REPORT" | awk -F'\t' -v c="$COMPLETENESS" -v x="$CONTAMINATION" '$2>=c && $3<=x' | wc -l)
FILTERED=$(tail -n +2 "$QUALITY_REPORT" | awk -F'\t' -v c="$COMPLETENESS" -v x="$CONTAMINATION" '$2<c || $3>x' | wc -l)

log "MAG quality summary based on CheckM2:"
log "  High quality-like completeness>=90, contamination<=5 : $HIGH_QUALITY"
log "  Good MAGs completeness>=$COMPLETENESS, contamination<=$CONTAMINATION : $GOOD_QUALITY"
log "  Filtered out completeness<$COMPLETENESS or contamination>$CONTAMINATION : $FILTERED"

if [ "$GOOD_QUALITY" -eq 0 ]; then
    log "[WARN] No MAGs passed the $COMPLETENESS/$CONTAMINATION CheckM2 filter"
    log "       GTDB-Tk and DRAM will have no good MAGs unless threshold is relaxed"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 12 — CREATE FILTERED TABLES
# ─────────────────────────────────────────────────────────────────────────────

log "STEP 3/4 — Creating filtered CheckM2 tables"

cp "$QUALITY_REPORT" "$ALL_TABLE"
log "All MAGs table: $ALL_TABLE"

# Good MAGs table: only MAGs passing 75/10 rule
head -n1 "$QUALITY_REPORT" > "$GOOD_TABLE_75_10"

tail -n +2 "$QUALITY_REPORT" | \
    awk -F'\t' -v c="$COMPLETENESS" -v x="$CONTAMINATION" '$2>=c && $3<=x' >> "$GOOD_TABLE_75_10"

GOOD_COUNT=$(tail -n +2 "$GOOD_TABLE_75_10" | wc -l)
log "Good MAGs using $COMPLETENESS/$CONTAMINATION: $GOOD_COUNT"

tail -n +2 "$GOOD_TABLE_75_10" | \
    awk -F'\t' '{print $1}' > "$GOOD_IDS_75_10"

# Generic filenames for downstream scripts
cp "$GOOD_TABLE_75_10" "$GOOD_TABLE"
cp "$GOOD_IDS_75_10" "$GOOD_IDS"

log "Good MAG table 75/10: $GOOD_TABLE_75_10"
log "Good MAG IDs 75/10  : $GOOD_IDS_75_10"
log "Generic good table  : $GOOD_TABLE"
log "Generic good IDs    : $GOOD_IDS"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 13 — COPY GOOD MAG FASTA FILES
# ─────────────────────────────────────────────────────────────────────────────

log "STEP 4/4 — Creating final good MAG FASTA folder for GTDB-Tk and DRAM"

# Clean and recreate the good MAG FASTA folder to avoid stale files
rm -rf "$GOOD_MAG_FASTA_DIR"
mkdir -p "$GOOD_MAG_FASTA_DIR"

: > "$COPIED_FASTA_TABLE"
: > "$MISSING_FASTA_LIST"

echo -e "sample_id\tmag_id\tsource_fasta\tgood_mag_fasta" > "$COPIED_FASTA_TABLE"

COPIED=0
MISSING=0

while IFS= read -r MAG_ID || [ -n "$MAG_ID" ]; do
    MAG_ID=$(echo "$MAG_ID" | tr -d '\r' | xargs)

    if [ -z "$MAG_ID" ]; then
        continue
    fi

    SRC=""

    # Try common FASTA filename patterns
    if [ -f "$BINS/${MAG_ID}.${EXT}" ]; then
        SRC="$BINS/${MAG_ID}.${EXT}"
    elif [ -f "$BINS/${MAG_ID}.fa" ]; then
        SRC="$BINS/${MAG_ID}.fa"
    elif [ -f "$BINS/${MAG_ID}.fasta" ]; then
        SRC="$BINS/${MAG_ID}.fasta"
    elif [ -f "$BINS/${MAG_ID}.fna" ]; then
        SRC="$BINS/${MAG_ID}.fna"
    elif [ -f "$BINS/${MAG_ID}" ]; then
        SRC="$BINS/${MAG_ID}"
    fi

    if [ -z "$SRC" ]; then
        echo "$MAG_ID" >> "$MISSING_FASTA_LIST"
        MISSING=$((MISSING + 1))
        continue
    fi

    # Standardize extension to .fa for downstream GTDB-Tk and DRAM
    DEST="$GOOD_MAG_FASTA_DIR/${MAG_ID}.fa"

    cp "$SRC" "$DEST"

    echo -e "${SAMPLE}\t${MAG_ID}\t${SRC}\t${DEST}" >> "$COPIED_FASTA_TABLE"

    COPIED=$((COPIED + 1))

done < "$GOOD_IDS"

GOOD_FASTA_COUNT=$(find "$GOOD_MAG_FASTA_DIR" -maxdepth 1 -name "*.fa" | wc -l)

log "Good MAG FASTA files copied: $COPIED"
log "Good MAG FASTA count in folder: $GOOD_FASTA_COUNT"
log "Missing good MAG FASTA files: $MISSING"
log "Good MAG FASTA folder: $GOOD_MAG_FASTA_DIR"
log "Copied FASTA path table: $COPIED_FASTA_TABLE"

if [ "$MISSING" -gt 0 ]; then
    log "[WARN] Some good MAG IDs did not match FASTA files."
    log "Missing FASTA list: $MISSING_FASTA_LIST"
fi

if [ "$GOOD_COUNT" -gt 0 ] && [ "$GOOD_FASTA_COUNT" -eq 0 ]; then
    echo "[ERROR] Good MAGs passed CheckM2, but no FASTA files were copied." | tee -a "$LOG"
    echo "        Check whether CheckM2 MAG IDs match FASTA filenames." | tee -a "$LOG"
    echo "        Good IDs file: $GOOD_IDS" | tee -a "$LOG"
    echo "        Source bins  : $BINS" | tee -a "$LOG"
    exit 1
fi

if [ "$GOOD_FASTA_COUNT" -ne "$GOOD_COUNT" ]; then
    log "[WARN] Good MAG table count and copied FASTA count differ."
    log "       Good MAG table count : $GOOD_COUNT"
    log "       Copied FASTA count   : $GOOD_FASTA_COUNT"
    log "       Check missing list   : $MISSING_FASTA_LIST"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 14 — COMPLETION SUMMARY
# ─────────────────────────────────────────────────────────────────────────────

{
    echo "============================================="
    echo " Finished: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================="
} >> "$LOG"

echo ""
echo "======================================================"
echo "  Step 09 COMPLETE — $SAMPLE"
echo "======================================================"
echo "  Total MAGs assessed   : $TOTAL_MAGS"
echo "  High quality-like     : $HIGH_QUALITY"
echo "  Good MAGs 75/10       : $GOOD_COUNT"
echo "  Filtered MAGs         : $FILTERED"
echo "  Good MAG FASTAs copied: $GOOD_FASTA_COUNT"
echo ""
echo "  Output files:"
echo "  Quality report        : $QUALITY_REPORT"
echo "  All MAGs table        : $ALL_TABLE"
echo "  Good MAGs table 75/10 : $GOOD_TABLE_75_10"
echo "  Good MAG IDs 75/10    : $GOOD_IDS_75_10"
echo "  Generic good table    : $GOOD_TABLE"
echo "  Generic good IDs      : $GOOD_IDS"
echo "  Good MAG FASTA folder : $GOOD_MAG_FASTA_DIR"
echo "  FASTA paths table     : $COPIED_FASTA_TABLE"
echo "  Missing FASTA list    : $MISSING_FASTA_LIST"
echo "  Log file              : $LOG"
echo ""
echo "  Key columns in quality_report.tsv:"
echo "  Col 1 : Name          → MAG/bin ID"
echo "  Col 2 : Completeness  → genome completeness percentage"
echo "  Col 3 : Contamination → contamination percentage"
echo ""
echo "  Filtering used for downstream MAGs:"
echo "  completeness >= $COMPLETENESS"
echo "  contamination <= $CONTAMINATION"
echo ""
echo "  This folder is now the official downstream MAG set:"
echo "  $GOOD_MAG_FASTA_DIR"
echo ""
echo "  Next step:"
echo "  bash scripts/10_gtdbtk.sh $SAMPLE"
echo "======================================================"