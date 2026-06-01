#!/bin/bash
# =============================================================================
# Script : 04_cdhit.sh
# Purpose: Filter short proteins and cluster using CD-HIT to produce a
#          non-redundant protein catalogue for functional annotation
#          NOTE: RGI/CARD in Script 05 uses the FULL unfiltered proteins.faa
#                CD-HIT output is used for KOfamScan/KEGG in Script 11 only
# Usage  : bash scripts/04_cdhit.sh <SAMPLE_ID>
# Example: bash scripts/04_cdhit.sh ERR12510647
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
    echo "Usage  : bash scripts/04_cdhit.sh <SAMPLE_ID>"
    echo "Example: bash scripts/04_cdhit.sh ERR12510647"
    echo ""
    exit 1
fi

SAMPLE=$1

echo ""
echo "======================================================"
echo "  Shotgun Metagenomics Pipeline — Step 04: CD-HIT"
echo "  Sample : $SAMPLE"
echo "  Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "======================================================"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 — CONDA SETUP
# ─────────────────────────────────────────────────────────────────────────────
source /home/scccs1/miniconda3/etc/profile.d/conda.sh

CONDA_ENV="shotgun_gene"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 — DEPENDENCY CHECK
# ─────────────────────────────────────────────────────────────────────────────
echo "[CHECK] Verifying tools in conda environment: $CONDA_ENV"

for tool in seqkit cd-hit; do
    if ! conda run -n "$CONDA_ENV" which "$tool" &>/dev/null; then
        echo "[ERROR] '$tool' not found in conda environment '$CONDA_ENV'"
        echo "        Fix: conda install -n $CONDA_ENV -c bioconda $tool"
        exit 1
    fi
done

# Version checks — seqkit and cd-hit use different version flags
SEQKIT_VER=$(conda run -n "$CONDA_ENV" seqkit version 2>&1 | head -n1 || true)
CDHIT_VER=$(conda run -n "$CONDA_ENV" cd-hit -h 2>&1 | grep -i "CD-HIT version" | head -n1 || true)
echo "[OK]    seqkit  — $SEQKIT_VER"
echo "[OK]    cd-hit  — $CDHIT_VER"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4 — PATH DEFINITIONS
# ─────────────────────────────────────────────────────────────────────────────
PROJECT=/mnt/e/kshiteeja/shotgun_project

GENES=$PROJECT/results/gene_prediction/$SAMPLE
CDHIT=$PROJECT/results/cdhit/$SAMPLE
LOGS=$PROJECT/logs

mkdir -p "$CDHIT" "$LOGS"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 5 — INPUT FILE CHECK
# ─────────────────────────────────────────────────────────────────────────────
# IMPORTANT: Must match output filename from 03_gene_prediction.sh
PROTEINS=$GENES/${SAMPLE}_proteins.faa

echo "[CHECK] Verifying protein input..."

if [ ! -f "$PROTEINS" ]; then
    echo "[ERROR] Missing protein file:"
    echo "        $PROTEINS"
    echo "        Run gene prediction first: bash scripts/03_gene_prediction.sh $SAMPLE"
    exit 1
fi

if [ ! -s "$PROTEINS" ]; then
    echo "[ERROR] Protein file exists but is empty:"
    echo "        $PROTEINS"
    exit 1
fi

ORIGINAL_COUNT=$(grep -c "^>" "$PROTEINS")
PROTEIN_SIZE=$(du -sh "$PROTEINS" | cut -f1)

echo "[OK]    Protein file : $PROTEINS"
echo "[OK]    File size    : $PROTEIN_SIZE"
echo "[OK]    Protein count: $ORIGINAL_COUNT"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 6 — OUTPUT FILE DEFINITIONS
# ─────────────────────────────────────────────────────────────────────────────
# All files prefixed with sample ID for unambiguous identification in Python/R
PROTEINS_100AA=$CDHIT/${SAMPLE}_proteins_100aa.faa    # length-filtered proteins
PROTEINS_NR=$CDHIT/${SAMPLE}_proteins_nr.faa          # non-redundant proteins
CLUSTER_FILE=${PROTEINS_NR}.clstr                      # CD-HIT cluster membership
LOG=$LOGS/${SAMPLE}_04_cdhit.log

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 7 — THREAD + MEMORY SETTINGS
# ─────────────────────────────────────────────────────────────────────────────
THREADS=16
# CD-HIT memory is specified in MB
# Setting to 60000 MB = 60 GB
# Matches available WSL RAM profile (73GB total, 60GB safe limit)
MEMORY=60000

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 8 — RESUME LOGIC
# ─────────────────────────────────────────────────────────────────────────────
if [ -s "$PROTEINS_100AA" ] && [ -s "$PROTEINS_NR" ] && [ -s "$CLUSTER_FILE" ]; then
    echo ""
    echo "[SKIP] CD-HIT already complete for sample: $SAMPLE"
    echo "       Filtered proteins : $PROTEINS_100AA"
    echo "       NR proteins       : $PROTEINS_NR"
    echo "       Cluster file      : $CLUSTER_FILE"
    echo "       Delete these files to force rerun."
    echo ""
    exit 0
fi

# Remove partial outputs before rerun
if [ -f "$PROTEINS_100AA" ] || [ -f "$PROTEINS_NR" ] || [ -f "$CLUSTER_FILE" ]; then
    echo "[WARN] Partial CD-HIT output found. Removing incomplete files."
    rm -f "$PROTEINS_100AA" "$PROTEINS_NR" "$CLUSTER_FILE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 9 — LOG INITIALISATION
# ─────────────────────────────────────────────────────────────────────────────
{
    echo "============================================="
    echo " Script  : 04_cdhit.sh"
    echo " Sample  : $SAMPLE"
    echo " Started : $(date '+%Y-%m-%d %H:%M:%S')"
    echo " Input   : $PROTEINS"
    echo " Proteins: $ORIGINAL_COUNT"
    echo " Min len : 100 aa"
    echo " Identity: 0.95"
    echo " Threads : $THREADS"
    echo " Memory  : ${MEMORY} MB"
    echo "---------------------------------------------"
    echo " NOTE: This output is for KOfamScan/KEGG only"
    echo "       RGI/CARD uses full unfiltered proteins"
    echo "============================================="
} > "$LOG"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 10 — FILTER SHORT PROTEINS (< 100 amino acids)
# ─────────────────────────────────────────────────────────────────────────────
log "STEP 1/3 — seqkit: filtering proteins shorter than 100 amino acids"
log "Reason: proteins < 100aa are often fragments and reduce ARG/KEGG hit quality"

conda run -n "$CONDA_ENV" seqkit seq \
    -m 100 \
    "$PROTEINS" \
    -o "$PROTEINS_100AA" \
    2>&1 | tee -a "$LOG"

if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo "[ERROR] seqkit filtering failed for sample: $SAMPLE"
    echo "        Check log: $LOG"
    exit 1
fi

if [ ! -s "$PROTEINS_100AA" ]; then
    echo "[ERROR] Filtered protein file is empty: $PROTEINS_100AA"
    echo "        All proteins were shorter than 100aa — check assembly quality"
    exit 1
fi

FILTERED_COUNT=$(grep -c "^>" "$PROTEINS_100AA")
REMOVED=$((ORIGINAL_COUNT - FILTERED_COUNT))

log "Proteins before filtering : $ORIGINAL_COUNT"
log "Proteins after filtering  : $FILTERED_COUNT"
log "Proteins removed (<100aa) : $REMOVED"

if [ "$FILTERED_COUNT" -lt 100 ]; then
    log "[WARN] Very few proteins remain after filtering ($FILTERED_COUNT)"
    log "       Check contig quality and assembly completeness"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 11 — CD-HIT CLUSTERING
# ─────────────────────────────────────────────────────────────────────────────
log "STEP 2/3 — CD-HIT: clustering at 95% identity"
log "Parameters: -c 0.95 -aS 0.9 -G 0 -g 1 -T $THREADS -M $MEMORY"
log "Purpose   : non-redundant protein set for KOfamScan/KEGG annotation"

conda run -n "$CONDA_ENV" cd-hit \
    -i "$PROTEINS_100AA" \
    -o "$PROTEINS_NR" \
    -c 0.95 \
    -aS 0.9 \
    -G 0 \
    -g 1 \
    -T "$THREADS" \
    -M "$MEMORY" \
    2>&1 | tee -a "$LOG"

if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo "[ERROR] CD-HIT failed for sample: $SAMPLE"
    echo "        Check log: $LOG"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 12 — OUTPUT VALIDATION
# ─────────────────────────────────────────────────────────────────────────────
log "STEP 3/3 — Validating CD-HIT outputs"

if [ ! -s "$PROTEINS_NR" ]; then
    echo "[ERROR] CD-HIT output missing or empty: $PROTEINS_NR"
    exit 1
fi

if [ ! -s "$CLUSTER_FILE" ]; then
    echo "[ERROR] CD-HIT cluster file missing or empty: $CLUSTER_FILE"
    exit 1
fi

NR_COUNT=$(grep -c "^>" "$PROTEINS_NR")
CLUSTER_COUNT=$(grep -c "^>Cluster" "$CLUSTER_FILE")
NR_SIZE=$(du -sh "$PROTEINS_NR" | cut -f1)

log "Original proteins          : $ORIGINAL_COUNT"
log "After length filter >=100aa: $FILTERED_COUNT"
log "After CD-HIT 95% clustering: $NR_COUNT"
log "Total CD-HIT clusters      : $CLUSTER_COUNT"
log "NR protein file size       : $NR_SIZE"

# Show first 3 NR protein headers
log "Sample NR protein headers (first 3):"
grep "^>" "$PROTEINS_NR" | head -3 | tee -a "$LOG"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 13 — COMPLETION SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
{
    echo "============================================="
    echo " Finished: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================="
} >> "$LOG"

echo ""
echo "======================================================"
echo "  Step 04 COMPLETE — $SAMPLE"
echo "======================================================"
echo "  Original proteins    : $ORIGINAL_COUNT"
echo "  After >=100aa filter : $FILTERED_COUNT"
echo "  After CD-HIT 95%     : $NR_COUNT"
echo "  Clusters formed      : $CLUSTER_COUNT"
echo "  NR protein file      : $PROTEINS_NR"
echo "  Cluster file         : $CLUSTER_FILE"
echo "  Log file             : $LOG"
echo ""
echo "  REMINDER: Script 05 (RGI/CARD) uses full proteins:"
echo "  $GENES/${SAMPLE}_proteins.faa"
echo ""
echo "  Next step            : bash scripts/05_rgi.sh $SAMPLE"
echo "======================================================"