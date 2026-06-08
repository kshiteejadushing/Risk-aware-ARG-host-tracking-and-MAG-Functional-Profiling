#!/bin/bash
# =============================================================================
# Script : 05_rgi_arg_detection.sh
# Purpose: Detect antimicrobial resistance genes (ARGs) from predicted proteins
#          using RGI/CARD database
#          Input: Full Prodigal protein output — NO CD-HIT filtering
#          Reason: CD-HIT removes ARG variants — all proteins must be scanned
# Usage  : bash scripts/05_rgi_arg_detection.sh <SAMPLE_ID>
# Example: bash scripts/05_rgi_arg_detection.sh ERR12510647
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
    echo "Usage  : bash scripts/05_rgi_arg_detection.sh <SAMPLE_ID>"
    echo "Example: bash scripts/05_rgi_arg_detection.sh ERR12510647"
    echo ""
    exit 1
fi

SAMPLE=$1

echo ""
echo "======================================================"
echo "  Shotgun Metagenomics Pipeline — Step 05: RGI ARG Detection"
echo "  Sample : $SAMPLE"
echo "  Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "======================================================"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 — CONDA SETUP
# ─────────────────────────────────────────────────────────────────────────────
source /home/scccs1/miniconda3/etc/profile.d/conda.sh

CONDA_ENV="shotgun_arg"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 — DEPENDENCY CHECK
# ─────────────────────────────────────────────────────────────────────────────
echo "[CHECK] Verifying RGI in conda environment: $CONDA_ENV"

if ! conda run -n "$CONDA_ENV" which rgi &>/dev/null; then
    echo "[ERROR] rgi not found in conda environment '$CONDA_ENV'"
    echo "        Fix: conda install -n $CONDA_ENV -c bioconda rgi"
    exit 1
fi

RGI_VERSION=$(conda run -n "$CONDA_ENV" rgi -v 2>&1 | head -n1 || true)
echo "[OK]    rgi — $RGI_VERSION"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4 — PATH DEFINITIONS
# ─────────────────────────────────────────────────────────────────────────────
PROJECT=/mnt/e/kshiteeja/shotgun_project
CARD_DIR=/mnt/e/Databases/CARD
GENES=$PROJECT/results/gene_prediction/$SAMPLE
ARGS=$PROJECT/results/ARGs/$SAMPLE
LOGS=$PROJECT/logs

mkdir -p "$ARGS" "$LOGS"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 5 — INPUT FILE CHECK
# ─────────────────────────────────────────────────────────────────────────────
# FULL Prodigal proteins — not filtered, not clustered
# Every protein must be scanned to detect all ARG variants
PROTEINS=$GENES/${SAMPLE}_proteins.faa

echo "[CHECK] Verifying full protein input from Prodigal..."

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

PROTEIN_COUNT=$(grep -c "^>" "$PROTEINS")
PROTEIN_SIZE=$(du -sh "$PROTEINS" | cut -f1)

echo "[OK]    Protein file  : $PROTEINS"
echo "[OK]    Protein count : $PROTEIN_COUNT"
echo "[OK]    File size     : $PROTEIN_SIZE"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 6 — OUTPUT FILE DEFINITIONS
# ─────────────────────────────────────────────────────────────────────────────
OUTPREFIX=$ARGS/${SAMPLE}_rgi
RGI_TXT=${OUTPREFIX}.txt
RGI_JSON=${OUTPREFIX}.json
LOG=$LOGS/${SAMPLE}_05_rgi_arg_detection.log

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 7 — THREAD SETTINGS
# ─────────────────────────────────────────────────────────────────────────────
THREADS=16

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 8 — RESUME LOGIC
# ─────────────────────────────────────────────────────────────────────────────
if [ -s "$RGI_TXT" ]; then
    echo ""
    echo "[SKIP] RGI already complete for sample: $SAMPLE"
    echo "       RGI TXT : $RGI_TXT"
    echo "       RGI JSON: $RGI_JSON"
    echo "       Delete these files to force rerun."
    echo ""
    exit 0
fi

# Remove partial RGI outputs before rerun
if [ -f "$RGI_TXT" ] || [ -f "$RGI_JSON" ]; then
    echo "[WARN] Partial RGI output found. Removing incomplete files."
    rm -f "$RGI_TXT" "$RGI_JSON" \
          "${OUTPREFIX}.temp" \
          "${OUTPREFIX}.txt.temp" \
          "${OUTPREFIX}.json.temp" \
          "${OUTPREFIX}.xml" 2>/dev/null || true
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 9 — LOG INITIALISATION
# ─────────────────────────────────────────────────────────────────────────────
{
    echo "============================================="
    echo " Script  : 05_rgi_arg_detection.sh"
    echo " Sample  : $SAMPLE"
    echo " Started : $(date '+%Y-%m-%d %H:%M:%S')"
    echo " Tool    : RGI/CARD"
    echo " Input   : $PROTEINS"
    echo " Proteins: $PROTEIN_COUNT"
    echo " Threads : $THREADS"
    echo " Aligner : DIAMOND"
    echo " Mode    : protein"
    echo " DB mode : local"
    echo "============================================="
} > "$LOG"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 10 — CHECK CARD DATABASE
# ─────────────────────────────────────────────────────────────────────────────
log "STEP 1/3 — Verifying CARD local database"

if [ ! -d "$CARD_DIR/localDB" ]; then
    echo "[ERROR] CARD localDB folder not found:" | tee -a "$LOG"
    echo "        $CARD_DIR/localDB" | tee -a "$LOG"
    exit 1
fi

CARD_CHECK=$(cd "$CARD_DIR" && conda run -n "$CONDA_ENV" rgi database --version --local 2>&1 || true)

if echo "$CARD_CHECK" | grep -qi "error\|not found\|no card\|cannot\|missing"; then
    echo "[ERROR] CARD local database not usable from: $CARD_DIR/localDB" | tee -a "$LOG"
    echo "$CARD_CHECK" | tee -a "$LOG"
    exit 1
fi

log "CARD database confirmed from: $CARD_DIR/localDB"
log "$CARD_CHECK"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 11 — RUN RGI
# ─────────────────────────────────────────────────────────────────────────────
log "STEP 2/3 — Running RGI ARG detection"
log "Input   : $PROTEINS ($PROTEIN_COUNT proteins)"
log "Output  : $OUTPREFIX"
log "Aligner : DIAMOND"
log "Threads : $THREADS"

(
    cd "$CARD_DIR"

    conda run -n "$CONDA_ENV" rgi main \
        -i "$PROTEINS" \
        -o "$OUTPREFIX" \
        -t protein \
        -a DIAMOND \
        --local \
        --clean \
        -n "$THREADS"
) 2>&1 | tee -a "$LOG"

if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo "[ERROR] RGI failed for sample: $SAMPLE"
    echo "        Check log: $LOG"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 12 — OUTPUT VALIDATION
# ─────────────────────────────────────────────────────────────────────────────
log "STEP 3/3 — Validating RGI outputs"

if [ ! -s "$RGI_TXT" ]; then
    echo "[ERROR] RGI TXT output missing or empty: $RGI_TXT"
    echo "        This may mean no ARGs were detected OR RGI crashed silently."
    echo "        Check log: $LOG"
    exit 1
fi

if [ ! -f "$RGI_JSON" ]; then
    log "[WARN] RGI JSON not produced — only TXT available"
fi

# Count hits by confidence tier
ARG_HITS=$(tail -n +2 "$RGI_TXT" | wc -l)

# Automatically find the Cut_Off column number from the RGI header
CUTOFF_COL=$(head -n 1 "$RGI_TXT" | awk -F'\t' '
{
    for (i=1; i<=NF; i++) {
        if ($i == "Cut_Off" || $i == "Cut Off" || $i == "Cutoff") {
            print i
            exit
        }
    }
}')

if [ -z "$CUTOFF_COL" ]; then
    echo "[ERROR] Could not find Cut_Off column in RGI output header." | tee -a "$LOG"
    echo "        Check RGI TXT header with:" | tee -a "$LOG"
    echo "        head -n 1 $RGI_TXT | tr '\t' '\n' | nl" | tee -a "$LOG"
    exit 1
fi

log "Detected RGI Cut_Off column: $CUTOFF_COL"

STRICT_HITS=$(tail -n +2 "$RGI_TXT" | awk -F'\t' -v col="$CUTOFF_COL" '$col=="Perfect" || $col=="Strict"' | wc -l)
LOOSE_HITS=$(tail -n +2 "$RGI_TXT" | awk -F'\t' -v col="$CUTOFF_COL" '$col=="Loose"' | wc -l)

log "Total ARG hits     : $ARG_HITS"
log "Perfect+Strict     : $STRICT_HITS  ← use these for thesis analysis"
log "Loose hits         : $LOOSE_HITS   ← interpret carefully"

# Warn if no strict hits — unexpected for sewage samples
if [ "$STRICT_HITS" -eq 0 ]; then
    log "[WARN] No Perfect or Strict ARG hits found."
    log "       For sewage metagenomics this is unexpected."
    log "       Check: correct protein file used, CARD database loaded correctly"
fi

# Show first 5 hits for manual verification
log "First 5 RGI hits:"
head -n 6 "$RGI_TXT" | tee -a "$LOG"

RGI_SIZE=$(du -sh "$RGI_TXT" | cut -f1)
log "RGI TXT file size: $RGI_SIZE"

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
echo "  Step 05 COMPLETE — $SAMPLE"
echo "======================================================"
echo "  Proteins scanned    : $PROTEIN_COUNT"
echo "  Total ARG hits      : $ARG_HITS"
echo "  Perfect+Strict hits : $STRICT_HITS"
echo "  Loose hits          : $LOOSE_HITS"
echo "  RGI TXT             : $RGI_TXT"
echo "  RGI JSON            : $RGI_JSON"
echo "  Log file            : $LOG"
echo ""
echo "  Key RGI TXT columns for downstream linking:"
echo "  Col 1  : ORF_ID            → Prodigal gene ID → contig ID"
echo "  Col 9  : Best_Hit_ARO      → ARG name"
echo "  Col 12 : Drug Class        → resistance category"
echo "  Col 14 : Resistance Mechanism"
echo "  Col 16 : AMR Gene Family"
echo "  Cut_Off : column is auto-detected by the script           → Perfect/Strict/Loose"
echo ""
echo "  Next step: bash scripts/06_binning.sh $SAMPLE"
echo "======================================================"