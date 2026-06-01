#!/bin/bash
# =============================================================================
# Script : 07_metawrap_binning.sh
# Purpose: Run metaWRAP binning using MetaBAT2, MaxBin2, and CONCOCT
# Usage  : bash scripts/07_metawrap_binning.sh <SAMPLE_ID>
# Example: bash scripts/07_metawrap_binning.sh ERR12510647
# Project: Shotgun Metagenomics — ARG detection, MAG binning, host taxonomy
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1 — ARGUMENT CHECK
# ─────────────────────────────────────────────────────────────────────────────
if [ $# -lt 1 ]; then
    echo ""
    echo "[ERROR] No sample ID provided."
    echo "Usage  : bash scripts/07_metawrap_binning.sh <SAMPLE_ID>"
    echo "Example: bash scripts/07_metawrap_binning.sh ERR12510647"
    echo ""
    exit 1
fi

SAMPLE=$1

echo ""
echo "======================================================"
echo "  Shotgun Metagenomics Pipeline — Step 07: metaWRAP Binning"
echo "  Sample : $SAMPLE"
echo "  Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "======================================================"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 — CONDA SETUP
# ─────────────────────────────────────────────────────────────────────────────
source /home/scccs1/miniconda3/etc/profile.d/conda.sh

CONDA_ENV="metawrap-env"

echo "[CHECK] Verifying metaWRAP in conda environment: $CONDA_ENV"

if ! conda run -n "$CONDA_ENV" which metawrap &>/dev/null; then
    echo "[ERROR] metaWRAP not found in conda environment: $CONDA_ENV"
    echo "        Check environment name or install/activate metaWRAP."
    exit 1
fi

MW_VERSION=$(conda run -n "$CONDA_ENV" metawrap -v 2>&1 | awk 'NR==1{print; exit}' || true)

if [ -z "$MW_VERSION" ]; then
    MW_VERSION="version not printed, but metawrap command was found"
fi

echo "[OK]    metaWRAP: $MW_VERSION"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 — PATH DEFINITIONS
# ─────────────────────────────────────────────────────────────────────────────
PROJECT=/mnt/e/kshiteeja/shotgun_project

MW_READS=$PROJECT/data/metawrap_reads/$SAMPLE
ASSEMBLY=$PROJECT/results/assembly/$SAMPLE
BINNING=$PROJECT/results/binning/$SAMPLE
LOGS=$PROJECT/logs

mkdir -p "$LOGS"

R1=$MW_READS/${SAMPLE}_1.fastq
R2=$MW_READS/${SAMPLE}_2.fastq

# Correct contig path for your project
CONTIGS=$ASSEMBLY/final.contigs.fa

LOG=$LOGS/${SAMPLE}_07_metawrap_binning.log

THREADS=16
MEMORY_GB=60

METABAT_BINS=$BINNING/metabat2_bins
MAXBIN_BINS=$BINNING/maxbin2_bins
CONCOCT_BINS=$BINNING/concoct_bins

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4 — HELPER FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"
}

count_bins() {
    local DIR=$1

    if [ ! -d "$DIR" ]; then
        echo 0
        return
    fi

    find "$DIR" -type f \( -name "*.fa" -o -name "*.fasta" -o -name "*.fna" \) 2>/dev/null | wc -l
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 5 — INPUT FILE CHECK
# ─────────────────────────────────────────────────────────────────────────────
echo "[CHECK] Verifying binning input files..."

if [ ! -s "$R1" ]; then
    echo "[ERROR] Missing or empty R1: $R1"
    echo "        Run: bash scripts/06_prepare_metawrap_reads.sh $SAMPLE"
    exit 1
fi

if [ ! -s "$R2" ]; then
    echo "[ERROR] Missing or empty R2: $R2"
    echo "        Run: bash scripts/06_prepare_metawrap_reads.sh $SAMPLE"
    exit 1
fi

if [ ! -s "$CONTIGS" ]; then
    echo "[ERROR] Missing or empty contigs: $CONTIGS"
    echo "        Run: bash scripts/02_assembly.sh $SAMPLE"
    exit 1
fi

R1_SIZE=$(du -sh "$R1" | cut -f1)
R2_SIZE=$(du -sh "$R2" | cut -f1)
CONTIG_SIZE=$(du -sh "$CONTIGS" | cut -f1)
CONTIG_COUNT=$(awk '/^>/ {count++} END{print count+0}' "$CONTIGS")

echo "[OK]    R1          : $R1 ($R1_SIZE)"
echo "[OK]    R2          : $R2 ($R2_SIZE)"
echo "[OK]    Contigs     : $CONTIGS ($CONTIG_SIZE)"
echo "[OK]    Contig count: $CONTIG_COUNT"

if [ "$CONTIG_COUNT" -eq 0 ]; then
    echo "[ERROR] No contigs found in: $CONTIGS"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 6 — DISK SPACE CHECK
# ─────────────────────────────────────────────────────────────────────────────
echo "[CHECK] Verifying available disk space on E drive..."

AVAIL_KB=$(df -Pk "$PROJECT" | awk 'NR==2{print $4}')
AVAIL_GB=$((AVAIL_KB / 1024 / 1024))

echo "[OK]    Available disk space: ${AVAIL_GB}GB"

if [ "$AVAIL_GB" -lt 100 ]; then
    echo "[ERROR] Insufficient disk space: only ${AVAIL_GB}GB free"
    echo "        metaWRAP binning needs at least 100GB free."
    echo "        Free space on /mnt/e before continuing."
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 7 — LOG INITIALISATION
# ─────────────────────────────────────────────────────────────────────────────
{
    echo "============================================="
    echo " Script  : 07_metawrap_binning.sh"
    echo " Sample  : $SAMPLE"
    echo " Started : $(date '+%Y-%m-%d %H:%M:%S')"
    echo " Tool    : metaWRAP binning"
    echo " Binners : MetaBAT2, MaxBin2, CONCOCT"
    echo " R1      : $R1"
    echo " R2      : $R2"
    echo " Contigs : $CONTIGS"
    echo " Count   : $CONTIG_COUNT contigs"
    echo " Output  : $BINNING"
    echo " Threads : $THREADS"
    echo " Memory  : ${MEMORY_GB}GB"
    echo " Disk    : ${AVAIL_GB}GB available"
    echo "============================================="
} > "$LOG"

log "Log file created: $LOG"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 8 — RESUME / RERUN LOGIC
# ─────────────────────────────────────────────────────────────────────────────
METABAT_COUNT=$(count_bins "$METABAT_BINS")
MAXBIN_COUNT=$(count_bins "$MAXBIN_BINS")
CONCOCT_COUNT=$(count_bins "$CONCOCT_BINS")

if [ "$METABAT_COUNT" -gt 0 ] && [ "$MAXBIN_COUNT" -gt 0 ] && [ "$CONCOCT_COUNT" -gt 0 ]; then
    log "[SKIP] metaWRAP binning already appears complete."
    log "MetaBAT2 bins: $METABAT_COUNT"
    log "MaxBin2 bins : $MAXBIN_COUNT"
    log "CONCOCT bins : $CONCOCT_COUNT"
    log "Output       : $BINNING"

    echo ""
    echo "[SKIP] metaWRAP binning already appears complete for sample: $SAMPLE"
    echo "       MetaBAT2 bins: $METABAT_COUNT"
    echo "       MaxBin2 bins : $MAXBIN_COUNT"
    echo "       CONCOCT bins : $CONCOCT_COUNT"
    echo "       Output       : $BINNING"
    echo ""
    exit 0
fi

if [ -d "$BINNING" ]; then
    log "[WARN] Incomplete previous binning folder found."
    log "Removing incomplete folder: $BINNING"
    rm -rf "$BINNING"
fi

mkdir -p "$BINNING"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 9 — RUN METAWRAP BINNING
# ─────────────────────────────────────────────────────────────────────────────
log "STEP 1/3 — Running metaWRAP binning"
log "Output folder: $BINNING"
log "Binners: MetaBAT2 + MaxBin2 + CONCOCT"

set +e

conda run -n "$CONDA_ENV" metawrap binning \
    -o "$BINNING" \
    -t "$THREADS" \
    -m "$MEMORY_GB" \
    -a "$CONTIGS" \
    --metabat2 \
    --maxbin2 \
    --concoct \
    "$R1" "$R2" \
    2>&1 | tee -a "$LOG"

STATUS=${PIPESTATUS[0]}

set -e

if [ "$STATUS" -ne 0 ]; then
    echo "[ERROR] metaWRAP binning failed for sample: $SAMPLE"
    echo "        Check log: $LOG"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 10 — VALIDATE OUTPUTS
# ─────────────────────────────────────────────────────────────────────────────
log "STEP 2/3 — Validating binning outputs"

if [ ! -d "$METABAT_BINS" ]; then
    echo "[ERROR] Missing MetaBAT2 bin folder: $METABAT_BINS"
    exit 1
fi

if [ ! -d "$MAXBIN_BINS" ]; then
    echo "[ERROR] Missing MaxBin2 bin folder: $MAXBIN_BINS"
    exit 1
fi

if [ ! -d "$CONCOCT_BINS" ]; then
    echo "[ERROR] Missing CONCOCT bin folder: $CONCOCT_BINS"
    exit 1
fi

METABAT_COUNT=$(count_bins "$METABAT_BINS")
MAXBIN_COUNT=$(count_bins "$MAXBIN_BINS")
CONCOCT_COUNT=$(count_bins "$CONCOCT_BINS")

log "MetaBAT2 bins: $METABAT_COUNT"
log "MaxBin2 bins : $MAXBIN_COUNT"
log "CONCOCT bins : $CONCOCT_COUNT"

if [ "$METABAT_COUNT" -eq 0 ]; then
    log "[WARN] MetaBAT2 produced zero bins."
fi

if [ "$MAXBIN_COUNT" -eq 0 ]; then
    log "[WARN] MaxBin2 produced zero bins."
fi

if [ "$CONCOCT_COUNT" -eq 0 ]; then
    log "[WARN] CONCOCT produced zero bins."
fi

if [ "$METABAT_COUNT" -eq 0 ] && [ "$MAXBIN_COUNT" -eq 0 ] && [ "$CONCOCT_COUNT" -eq 0 ]; then
    echo "[ERROR] All three binners produced zero bins."
    echo "        Binning completed, but no usable bins were generated."
    exit 1
fi

log "Binning output folder:"
ls -lh "$BINNING" | tee -a "$LOG"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 11 — DELETE SAM/BAM INTERMEDIATE FILES ONLY
# ─────────────────────────────────────────────────────────────────────────────
log "STEP 3/3 — Cleaning SAM/BAM intermediate files"

WORK_DIR=$BINNING/work_files

if [ -d "$WORK_DIR" ]; then
    log "Searching for SAM/BAM files in: $WORK_DIR"

    SAM_COUNT=$(find "$WORK_DIR" -type f -name "*.sam" 2>/dev/null | wc -l)
    BAM_COUNT=$(find "$WORK_DIR" -type f -name "*.bam" 2>/dev/null | wc -l)
    BAI_COUNT=$(find "$WORK_DIR" -type f \( -name "*.bai" -o -name "*.bam.bai" \) 2>/dev/null | wc -l)

    log "SAM files found: $SAM_COUNT"
    log "BAM files found: $BAM_COUNT"
    log "BAI files found: $BAI_COUNT"

    find "$WORK_DIR" -type f -name "*.sam" -delete 2>/dev/null || true
    find "$WORK_DIR" -type f -name "*.bam" -delete 2>/dev/null || true
    find "$WORK_DIR" -type f -name "*.bam.bai" -delete 2>/dev/null || true
    find "$WORK_DIR" -type f -name "*.bai" -delete 2>/dev/null || true

    log "SAM/BAM/BAI intermediate files deleted from work_files."
else
    log "No work_files directory found. Skipping SAM/BAM cleanup."
fi

# Keep uncompressed reads for possible reassemble_bins
MW_READS_DIR=$PROJECT/data/metawrap_reads/$SAMPLE

if [ -d "$MW_READS_DIR" ]; then
    READS_SIZE=$(du -sh "$MW_READS_DIR" | cut -f1)
    log "Uncompressed metaWRAP reads kept: $MW_READS_DIR ($READS_SIZE)"
    log "Do not delete yet if you may run reassemble_bins."
fi

AVAIL_KB_AFTER=$(df -Pk "$PROJECT" | awk 'NR==2{print $4}')
AVAIL_GB_AFTER=$((AVAIL_KB_AFTER / 1024 / 1024))
log "Available disk space after cleanup: ${AVAIL_GB_AFTER}GB"

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
echo "  Step 07 COMPLETE — $SAMPLE"
echo "======================================================"
echo "  Binning output : $BINNING"
echo "  MetaBAT2 bins  : $METABAT_COUNT"
echo "  MaxBin2 bins   : $MAXBIN_COUNT"
echo "  CONCOCT bins   : $CONCOCT_COUNT"
echo "  Log file       : $LOG"
echo ""
echo "  Kept reads for possible reassemble_bins:"
echo "  $MW_READS_DIR"
echo ""
echo "  Next step:"
echo "  bash scripts/08_metawrap_bin_refinement.sh $SAMPLE"
echo "======================================================"