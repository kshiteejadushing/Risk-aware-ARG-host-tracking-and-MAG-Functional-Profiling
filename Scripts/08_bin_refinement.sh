#!/bin/bash
# =============================================================================
# Script : 08_bin_refinement.sh
# Purpose: Refine bins from available binners using metaWRAP bin_refinement.
#          Supports MetaBAT2, MaxBin2, and CONCOCT, but does not require all.
#
# Safety rule:
#          At least 2 usable binner outputs are required.
#          If only 1 binner produced bins, bin_refinement is skipped/stopped
#          because metaWRAP bin_refinement is meant to compare/refine bin sets.
#
# Usage  : bash scripts/08_bin_refinement.sh <SAMPLE_ID>
# Example: bash scripts/08_bin_refinement.sh ERR12510647
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
    echo "Usage  : bash scripts/08_bin_refinement.sh <SAMPLE_ID>"
    echo "Example: bash scripts/08_bin_refinement.sh ERR12510647"
    echo ""
    exit 1
fi

SAMPLE=$1

echo ""
echo "======================================================"
echo "  Shotgun Metagenomics Pipeline — Step 08: Bin Refinement"
echo "  Sample : $SAMPLE"
echo "  Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "======================================================"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 — CONDA SETUP
# ─────────────────────────────────────────────────────────────────────────────
source /home/scccs1/miniconda3/etc/profile.d/conda.sh

CONDA_ENV="metawrap-env"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 — DEPENDENCY CHECK
# ─────────────────────────────────────────────────────────────────────────────
echo "[CHECK] Verifying metaWRAP in conda environment: $CONDA_ENV"

if ! conda run -n "$CONDA_ENV" which metawrap &>/dev/null; then
    echo "[ERROR] metaWRAP not found in conda environment '$CONDA_ENV'"
    echo "        Fix: conda install -n $CONDA_ENV -c bioconda metawrap"
    exit 1
fi

MW_VERSION=$(conda run -n "$CONDA_ENV" metawrap -v 2>&1 | head -n1 || true)
echo "[OK]    metaWRAP — $MW_VERSION"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4 — PATH DEFINITIONS
# ─────────────────────────────────────────────────────────────────────────────
PROJECT=/mnt/e/kshiteeja/shotgun_project

BINNING=$PROJECT/results/binning/$SAMPLE
REFINED=$PROJECT/results/bin_refinement/$SAMPLE
MW_READS=$PROJECT/data/metawrap_reads/$SAMPLE
LOGS=$PROJECT/logs

mkdir -p "$LOGS"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 5 — INPUT BIN FOLDER CHECK
# ─────────────────────────────────────────────────────────────────────────────
METABAT_BINS=$BINNING/metabat2_bins
MAXBIN_BINS=$BINNING/maxbin2_bins
CONCOCT_BINS=$BINNING/concoct_bins

echo "[CHECK] Verifying available input bin folders and bin counts..."

METABAT_COUNT=0
MAXBIN_COUNT=0
CONCOCT_COUNT=0

METABAT_ARG=""
MAXBIN_ARG=""
CONCOCT_ARG=""

AVAILABLE_BINNERS=0

# ---- MetaBAT2 check ----
if [ -d "$METABAT_BINS" ]; then
    METABAT_COUNT=$(find "$METABAT_BINS" \( -name "*.fa" -o -name "*.fasta" \) 2>/dev/null | wc -l)

    if [ "$METABAT_COUNT" -gt 0 ]; then
        echo "[OK]    MetaBAT2 bins found : $METABAT_COUNT"
        METABAT_ARG="-A $METABAT_BINS"
        AVAILABLE_BINNERS=$((AVAILABLE_BINNERS + 1))
    else
        echo "[WARN]  MetaBAT2 folder exists but contains zero .fa/.fasta bins. Skipping MetaBAT2."
    fi
else
    echo "[WARN]  MetaBAT2 bin folder not found. Skipping MetaBAT2."
fi

# ---- MaxBin2 check ----
if [ -d "$MAXBIN_BINS" ]; then
    MAXBIN_COUNT=$(find "$MAXBIN_BINS" \( -name "*.fa" -o -name "*.fasta" \) 2>/dev/null | wc -l)

    if [ "$MAXBIN_COUNT" -gt 0 ]; then
        echo "[OK]    MaxBin2 bins found  : $MAXBIN_COUNT"
        MAXBIN_ARG="-B $MAXBIN_BINS"
        AVAILABLE_BINNERS=$((AVAILABLE_BINNERS + 1))
    else
        echo "[WARN]  MaxBin2 folder exists but contains zero .fa/.fasta bins. Skipping MaxBin2."
    fi
else
    echo "[WARN]  MaxBin2 bin folder not found. Skipping MaxBin2."
fi

# ---- CONCOCT check ----
if [ -d "$CONCOCT_BINS" ]; then
    CONCOCT_COUNT=$(find "$CONCOCT_BINS" \( -name "*.fa" -o -name "*.fasta" \) 2>/dev/null | wc -l)

    if [ "$CONCOCT_COUNT" -gt 0 ]; then
        echo "[OK]    CONCOCT bins found  : $CONCOCT_COUNT"
        CONCOCT_ARG="-C $CONCOCT_BINS"
        AVAILABLE_BINNERS=$((AVAILABLE_BINNERS + 1))
    else
        echo "[WARN]  CONCOCT folder exists but contains zero .fa/.fasta bins. Skipping CONCOCT."
    fi
else
    echo "[WARN]  CONCOCT bin folder not found. Skipping CONCOCT."
fi

TOTAL_INPUT=$((METABAT_COUNT + MAXBIN_COUNT + CONCOCT_COUNT))

echo ""
echo "[SUMMARY] Input bin counts before refinement:"
echo "          MetaBAT2 : $METABAT_COUNT"
echo "          MaxBin2  : $MAXBIN_COUNT"
echo "          CONCOCT  : $CONCOCT_COUNT"
echo "          Total    : $TOTAL_INPUT"
echo "          Usable binner sets: $AVAILABLE_BINNERS"
echo ""

# Safety rule: metaWRAP bin_refinement needs at least two usable binner sets
if [ "$AVAILABLE_BINNERS" -lt 2 ]; then
    echo "[ERROR] Fewer than 2 binner sets contain bins."
    echo "        Usable binner sets found: $AVAILABLE_BINNERS"
    echo ""
    echo "        metaWRAP bin_refinement is meant to compare/refine multiple bin sets."
    echo "        If only one binner worked, do not run bin_refinement."
    echo "        Instead, run CheckM2 directly on that single bin folder."
    echo ""
    echo "        Current counts:"
    echo "        MetaBAT2 : $METABAT_COUNT"
    echo "        MaxBin2  : $MAXBIN_COUNT"
    echo "        CONCOCT  : $CONCOCT_COUNT"
    echo ""
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 6 — OUTPUT + SETTINGS
# ─────────────────────────────────────────────────────────────────────────────
LOG=$LOGS/${SAMPLE}_08_bin_refinement.log

THREADS=16

# RAM: WSL usable = ~73GB, safe limit = 60GB
MEMORY_GB=60

# MAG quality thresholds:
# Completeness >= 50% = medium-quality MAG threshold
# Completeness >= 75% = stricter threshold, may recover fewer MAGs
# Completeness >= 90% = high-quality MAG threshold
# Contamination <= 10% = acceptable
#
# Recommendation:
# If very few refined MAGs are recovered, change COMPLETENESS=50 and rerun.
COMPLETENESS=75
CONTAMINATION=10

# metaWRAP names the refined bin folder based on -c and -x values
REFINED_BINS=$REFINED/metawrap_${COMPLETENESS}_${CONTAMINATION}_bins
STATS_FILE=$REFINED/metawrap_${COMPLETENESS}_${CONTAMINATION}_bins.stats

# Set to "yes" to delete uncompressed reads after refinement
# Set to "no" to keep them
CLEANUP_READS="yes"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 7 — RESUME LOGIC
# ─────────────────────────────────────────────────────────────────────────────
REFINED_COUNT=0
if [ -d "$REFINED_BINS" ]; then
    REFINED_COUNT=$(find "$REFINED_BINS" -name "*.fa" 2>/dev/null | wc -l)
fi

if [ -d "$REFINED_BINS" ] && [ "$REFINED_COUNT" -gt 0 ]; then
    echo ""
    echo "[SKIP] Bin refinement already complete for sample: $SAMPLE"
    echo "       Refined bins : $REFINED_BINS"
    echo "       Refined count: $REFINED_COUNT"
    echo "       Delete $REFINED to force rerun."
    echo ""

    if [ "$CLEANUP_READS" = "yes" ] && [ -d "$MW_READS" ]; then
        echo "[CLEANUP] Removing uncompressed reads because refinement already exists:"
        echo "          $MW_READS"
        rm -rf "$MW_READS"
    fi

    exit 0
fi

# Remove incomplete output from previous failed run
if [ -d "$REFINED" ]; then
    echo "[WARN] Incomplete bin refinement output found. Removing:"
    echo "       $REFINED"
    rm -rf "$REFINED"
fi

mkdir -p "$REFINED"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 8 — LOG INITIALISATION
# ─────────────────────────────────────────────────────────────────────────────
{
    echo "============================================="
    echo " Script       : 08_bin_refinement.sh"
    echo " Sample       : $SAMPLE"
    echo " Started      : $(date '+%Y-%m-%d %H:%M:%S')"
    echo " Tool         : metaWRAP bin_refinement"
    echo " MetaBAT2 bins: $METABAT_BINS ($METABAT_COUNT)"
    echo " MaxBin2 bins : $MAXBIN_BINS ($MAXBIN_COUNT)"
    echo " CONCOCT bins : $CONCOCT_BINS ($CONCOCT_COUNT)"
    echo " Binner sets  : $AVAILABLE_BINNERS"
    echo " Total input  : $TOTAL_INPUT bins"
    echo " Output       : $REFINED"
    echo " Refined bins : $REFINED_BINS"
    echo " Threads      : $THREADS"
    echo " Memory       : ${MEMORY_GB}GB"
    echo " Completeness : >= ${COMPLETENESS}%"
    echo " Contamination: <= ${CONTAMINATION}%"
    echo " Cleanup reads: $CLEANUP_READS"
    echo "============================================="
} > "$LOG"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 9 — RUN BIN REFINEMENT
# ─────────────────────────────────────────────────────────────────────────────
log "STEP 1/3 — Running metaWRAP bin_refinement"
log "Completeness threshold : >= ${COMPLETENESS}%"
log "Contamination threshold: <= ${CONTAMINATION}%"
log ""
log "Input bin counts before refinement:"
log "MetaBAT2 bins : $METABAT_COUNT"
log "MaxBin2 bins  : $MAXBIN_COUNT"
log "CONCOCT bins  : $CONCOCT_COUNT"
log "Total input   : $TOTAL_INPUT"
log "Binner sets used: $AVAILABLE_BINNERS"

if [ "$METABAT_COUNT" -eq 0 ]; then
    log "MetaBAT2 skipped"
fi

if [ "$MAXBIN_COUNT" -eq 0 ]; then
    log "MaxBin2 skipped"
fi

if [ "$CONCOCT_COUNT" -eq 0 ]; then
    log "CONCOCT skipped"
fi

log ""
log "Running command with available binner sets only."

# Important:
# METABAT_ARG, MAXBIN_ARG, and CONCOCT_ARG are intentionally unquoted below.
# Each expands either to "-A path", "-B path", "-C path", or nothing.
conda run -n "$CONDA_ENV" metawrap bin_refinement \
    -o "$REFINED" \
    -t "$THREADS" \
    -m "$MEMORY_GB" \
    $METABAT_ARG \
    $MAXBIN_ARG \
    $CONCOCT_ARG \
    -c "$COMPLETENESS" \
    -x "$CONTAMINATION" \
    2>&1 | tee -a "$LOG"

if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo "[ERROR] metaWRAP bin_refinement failed for sample: $SAMPLE"
    echo "        Check log: $LOG"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 10 — OUTPUT VALIDATION
# ─────────────────────────────────────────────────────────────────────────────
log "STEP 2/3 — Validating bin refinement outputs"

REFINED_COUNT=0

if [ ! -d "$REFINED_BINS" ]; then
    log "[WARN] Refined bins folder not found: $REFINED_BINS"
    log "       This means no bins passed completeness >= $COMPLETENESS"
    log "       and contamination <= $CONTAMINATION thresholds."
    log "       Consider lowering COMPLETENESS to 50 in this script."
    log "       Full output folder contents:"
    ls -lh "$REFINED" | tee -a "$LOG"
else
    REFINED_COUNT=$(find "$REFINED_BINS" -name "*.fa" 2>/dev/null | wc -l)
    log "Refined bins folder : $REFINED_BINS"
    log "Refined bin count   : $REFINED_COUNT"

    if [ "$REFINED_COUNT" -eq 0 ]; then
        log "[WARN] Refined bins folder exists but contains zero bins."
        log "       Consider lowering COMPLETENESS threshold to 50."
    fi
fi

# Display stats file — useful for thesis methods/results
if [ -f "$STATS_FILE" ]; then
    log "Refined bin quality stats:"
    log "Format depends on metaWRAP output version."
    cat "$STATS_FILE" | tee -a "$LOG"
else
    log "[WARN] Stats file not found: $STATS_FILE"
fi

log ""
log "Before/after bin count summary:"
log "MetaBAT2 input bins : $METABAT_COUNT"
log "MaxBin2 input bins  : $MAXBIN_COUNT"
log "CONCOCT input bins  : $CONCOCT_COUNT"
log "Total input bins    : $TOTAL_INPUT"
log "Refined bins kept   : $REFINED_COUNT"

log "Full output folder contents:"
ls -lh "$REFINED" | tee -a "$LOG"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 11 — CLEANUP UNCOMPRESSED READS
# ─────────────────────────────────────────────────────────────────────────────
log "STEP 3/3 — Cleaning temporary uncompressed reads"

if [ "$CLEANUP_READS" = "yes" ]; then
    if [ -d "$MW_READS" ]; then
        READS_SIZE=$(du -sh "$MW_READS" | cut -f1)
        log "Deleting uncompressed reads: $MW_READS ($READS_SIZE)"
        log "Reason: no longer needed after binning and refinement"
        log "Note  : compressed reads in data/clean/ are never deleted"
        rm -rf "$MW_READS"
        log "Uncompressed reads deleted successfully"
    else
        log "Uncompressed reads already deleted or not present."
        log "Nothing to clean up."
    fi
else
    log "Cleanup disabled — uncompressed reads retained at: $MW_READS"
fi

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
echo "  Step 08 COMPLETE — $SAMPLE"
echo "======================================================"
echo "  Input bins before refinement:"
echo "    MetaBAT2      : $METABAT_COUNT"
echo "    MaxBin2       : $MAXBIN_COUNT"
echo "    CONCOCT       : $CONCOCT_COUNT"
echo "    Total input   : $TOTAL_INPUT"
echo "  Binner sets used: $AVAILABLE_BINNERS"
echo ""
echo "  Refined bins after refinement: $REFINED_COUNT"
echo "  Completeness threshold       : >= ${COMPLETENESS}%"
echo "  Contamination threshold      : <= ${CONTAMINATION}%"
echo ""
echo "  Refined folder : $REFINED_BINS"
echo "  Stats file     : $STATS_FILE"
echo "  Log file       : $LOG"
echo ""
echo "  These refined MAGs will be used for:"
echo "  → Script 09: CheckM2 quality assessment"
echo "  → Script 10: GTDB-Tk taxonomy assignment"
echo "  → Script 11/DRAM: MAG functional annotation"
echo "  → Final linking: ARG → contig → MAG → taxonomy → function"
echo ""
echo "  Next step: bash scripts/09_checkm2.sh $SAMPLE"
echo "======================================================"


#Refines available bin sets using `metaWRAP bin_refinement`.

#Features:

#- accepts a sample ID as input
#- checks MetaBAT2, MaxBin2, and CONCOCT bin folders
#- skips missing or empty binner outputs
#- requires at least two valid binner outputs for refinement
#- reports bin counts before and after refinement
#- logs all decisions and output paths
#- removes temporary uncompressed reads after successful refinement, if enabled

#Usage: bash scripts/08_bin_refinement.sh ERR12510647