#!/bin/bash
# =============================================================================
# Script : 06_prepare_metawrap_reads.sh
# Purpose: Decompress paired-end clean reads for metaWRAP binning
#          metaWRAP requires uncompressed FASTQ — cannot read .gz directly
#          These files are temporary — delete after binning to save disk space
# Usage  : bash scripts/06_prepare_metawrap_reads.sh <SAMPLE_ID>
# Example: bash scripts/06_prepare_metawrap_reads.sh ERR12510647
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
    echo "Usage  : bash scripts/06_prepare_metawrap_reads.sh <SAMPLE_ID>"
    echo "Example: bash scripts/06_prepare_metawrap_reads.sh ERR12510647"
    echo ""
    exit 1
fi

SAMPLE=$1

echo ""
echo "======================================================"
echo "  Shotgun Metagenomics Pipeline — Step 06: Prepare metaWRAP Reads"
echo "  Sample : $SAMPLE"
echo "  Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "======================================================"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 — DEPENDENCY CHECK
# ─────────────────────────────────────────────────────────────────────────────
echo "[CHECK] Verifying system tools..."

for tool in gzip df du; do
    if ! command -v "$tool" &>/dev/null; then
        echo "[ERROR] Required system tool not found: $tool"
        exit 1
    fi
done

echo "[OK]    gzip, df, du — all found"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 — PATH DEFINITIONS
# ─────────────────────────────────────────────────────────────────────────────
PROJECT=/mnt/e/kshiteeja/shotgun_project

CLEAN=$PROJECT/data/clean/$SAMPLE
MW_READS=$PROJECT/data/metawrap_reads/$SAMPLE
LOGS=$PROJECT/logs

mkdir -p "$MW_READS" "$LOGS"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4 — INPUT FILE CHECK
# ─────────────────────────────────────────────────────────────────────────────
CLEAN_R1=$CLEAN/${SAMPLE}_1.clean.fastq.gz
CLEAN_R2=$CLEAN/${SAMPLE}_2.clean.fastq.gz

echo "[CHECK] Verifying clean input reads..."

for f in "$CLEAN_R1" "$CLEAN_R2"; do
    if [ ! -f "$f" ]; then
        echo "[ERROR] Missing input file: $f"
        echo "        Run QC first: bash scripts/01_read_qc.sh $SAMPLE"
        exit 1
    fi
    if [ ! -s "$f" ]; then
        echo "[ERROR] Input file exists but is empty: $f"
        exit 1
    fi
done

echo "[OK]    Clean R1: $CLEAN_R1"
echo "[OK]    Clean R2: $CLEAN_R2"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 5 — GZIP INTEGRITY CHECK
# ─────────────────────────────────────────────────────────────────────────────
echo "[CHECK] Testing gzip integrity..."

for f in "$CLEAN_R1" "$CLEAN_R2"; do
    if ! gzip -t "$f" 2>/dev/null; then
        echo "[ERROR] Corrupt gzip file: $f"
        echo "        Re-run QC: bash scripts/01_read_qc.sh $SAMPLE"
        exit 1
    fi
done

echo "[OK]    Gzip integrity passed for both files"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 6 — OUTPUT FILE DEFINITIONS
# ─────────────────────────────────────────────────────────────────────────────
MW_R1=$MW_READS/${SAMPLE}_1.fastq
MW_R2=$MW_READS/${SAMPLE}_2.fastq
TMP_R1=${MW_R1}.tmp
TMP_R2=${MW_R2}.tmp
LOG=$LOGS/${SAMPLE}_06_prepare_metawrap_reads.log

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 7 — RESUME LOGIC
# ─────────────────────────────────────────────────────────────────────────────
if [ -s "$MW_R1" ] && [ -s "$MW_R2" ]; then
    echo ""
    echo "[SKIP] metaWRAP reads already prepared for sample: $SAMPLE"
    echo "       R1: $MW_R1"
    echo "       R2: $MW_R2"
    echo "       Delete these files to force rerun."
    echo ""
    exit 0
fi

# Remove partial or temp outputs before rerun
if [ -f "$MW_R1" ] || [ -f "$MW_R2" ] || \
   [ -f "$TMP_R1" ] || [ -f "$TMP_R2" ]; then
    echo "[WARN] Partial or temp files found. Removing before rerun."
    rm -f "$MW_R1" "$MW_R2" "$TMP_R1" "$TMP_R2"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 8 — LOG INITIALISATION
# ─────────────────────────────────────────────────────────────────────────────
{
    echo "============================================="
    echo " Script  : 06_prepare_metawrap_reads.sh"
    echo " Sample  : $SAMPLE"
    echo " Started : $(date '+%Y-%m-%d %H:%M:%S')"
    echo " Input R1: $CLEAN_R1"
    echo " Input R2: $CLEAN_R2"
    echo " Out R1  : $MW_R1"
    echo " Out R2  : $MW_R2"
    echo "============================================="
} > "$LOG"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 9 — DISK SPACE CHECK
# ─────────────────────────────────────────────────────────────────────────────
log "STEP 1/3 — Checking disk space before decompression"

CLEAN_R1_SIZE=$(du -sh "$CLEAN_R1" | cut -f1)
CLEAN_R2_SIZE=$(du -sh "$CLEAN_R2" | cut -f1)

log "Compressed R1 size : $CLEAN_R1_SIZE"
log "Compressed R2 size : $CLEAN_R2_SIZE"
log "Expected uncompressed size: approximately 3-4x larger than above"

# Check available disk space in GB
AVAIL_KB=$(df "$PROJECT" | tail -1 | awk '{print $4}')
AVAIL_GB=$((AVAIL_KB / 1024 / 1024))

log "Available disk space: ${AVAIL_GB}GB on $PROJECT"

# Require at least 50GB free before decompressing
if [ "$AVAIL_GB" -lt 50 ]; then
    echo "[ERROR] Insufficient disk space: only ${AVAIL_GB}GB free"
    echo "        At least 50GB required for uncompressed FASTQ files"
    echo "        Free space on /mnt/e/ before continuing"
    exit 1
fi

log "Disk space check passed: ${AVAIL_GB}GB available"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 10 — DECOMPRESS READS
# ─────────────────────────────────────────────────────────────────────────────
log "STEP 2/3 — Decompressing clean reads for metaWRAP"
log "Writing to temp files first to prevent incomplete outputs"

log "Decompressing R1..."
gzip -dc "$CLEAN_R1" > "$TMP_R1"

if [ ! -s "$TMP_R1" ]; then
    echo "[ERROR] Decompressed R1 is empty: $TMP_R1"
    rm -f "$TMP_R1"
    exit 1
fi

mv "$TMP_R1" "$MW_R1"
log "R1 decompressed: $MW_R1"

log "Decompressing R2..."
gzip -dc "$CLEAN_R2" > "$TMP_R2"

if [ ! -s "$TMP_R2" ]; then
    echo "[ERROR] Decompressed R2 is empty: $TMP_R2"
    rm -f "$TMP_R2"
    exit 1
fi

mv "$TMP_R2" "$MW_R2"
log "R2 decompressed: $MW_R2"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 11 — VERIFY OUTPUTS AND READ COUNT MATCH
# ─────────────────────────────────────────────────────────────────────────────
log "STEP 3/3 — Verifying outputs and paired-end read count match"

for f in "$MW_R1" "$MW_R2"; do
    if [ ! -s "$f" ]; then
        echo "[ERROR] Output file missing or empty: $f"
        exit 1
    fi
done

# Count reads in each file
# In FASTQ format every read = 4 lines
# Divide total lines by 4 to get read count
R1_LINES=$(wc -l < "$MW_R1")
R2_LINES=$(wc -l < "$MW_R2")
R1_READS=$((R1_LINES / 4))
R2_READS=$((R2_LINES / 4))

log "R1 reads: $R1_READS"
log "R2 reads: $R2_READS"

# Paired-end reads must be exactly equal
# Mismatch causes silent failures in BWA and metaWRAP
if [ "$R1_READS" -ne "$R2_READS" ]; then
    echo "[ERROR] Read count mismatch between R1 and R2"
    echo "        R1 reads: $R1_READS"
    echo "        R2 reads: $R2_READS"
    echo "        This will break metaWRAP binning."
    echo "        Re-run fastp QC: bash scripts/01_read_qc.sh $SAMPLE"
    exit 1
fi

log "Read count match confirmed: $R1_READS paired reads"

MW_R1_SIZE=$(du -sh "$MW_R1" | cut -f1)
MW_R2_SIZE=$(du -sh "$MW_R2" | cut -f1)

log "Decompressed R1 size: $MW_R1_SIZE"
log "Decompressed R2 size: $MW_R2_SIZE"

ls -lh "$MW_READS" | tee -a "$LOG"

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
echo "  Step 05 COMPLETE — $SAMPLE"
echo "======================================================"
echo "  R1 (uncompressed) : $MW_R1"
echo "  R2 (uncompressed) : $MW_R2"
echo "  Paired reads      : $R1_READS"
echo "  R1 size           : $MW_R1_SIZE"
echo "  R2 size           : $MW_R2_SIZE"
echo "  Log file          : $LOG"
echo ""
echo "  ⚠️  IMPORTANT:"
echo "  These files are large and temporary."
echo "  Keep them until Script 06 (binning) is complete."
echo "  After binning, delete them to recover disk space:"
echo "  rm -rf $MW_READS"
echo ""
echo "  Next step: bash scripts/06_binning.sh $SAMPLE"
echo "======================================================"