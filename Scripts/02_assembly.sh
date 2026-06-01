#!/bin/bash
# =============================================================================
# Script : 02_assembly.sh
# Purpose: De novo metagenomic assembly using MEGAHIT + quality check with QUAST
# Usage  : bash scripts/02_assembly.sh <SAMPLE_ID>
# Example: bash scripts/02_assembly.sh ERR12510647
# Author : Kshiteeja
# Project: Shotgun Metagenomics — ARG detection, MAG binning, host taxonomy
#
# IMPORTANT WSL NOTE:
# MEGAHIT cannot safely write its working output to /mnt/e because Windows-mounted
# drives do not support Linux FIFO/named pipe files required by MEGAHIT.
#
# Therefore:
#   - Clean reads are read from E drive.
#   - MEGAHIT + QUAST run inside WSL Linux filesystem: /home/scccs1/...
#   - Final contigs + QUAST reports are copied back to E drive.
#   - Temporary WSL assembly folder is deleted only after successful copy.
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1 — ARGUMENT CHECK
# ─────────────────────────────────────────────────────────────────────────────
if [ $# -lt 1 ]; then
    echo ""
    echo "[ERROR] No sample ID provided."
    echo "Usage  : bash scripts/02_assembly.sh <SAMPLE_ID>"
    echo "Example: bash scripts/02_assembly.sh ERR12510647"
    echo ""
    exit 1
fi

SAMPLE=$1

echo ""
echo "=================================================="
echo "  Shotgun Metagenomics Pipeline — Step 02: Assembly"
echo "  Sample : $SAMPLE"
echo "  Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================="

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 — CONDA SETUP
# ─────────────────────────────────────────────────────────────────────────────
source /home/scccs1/miniconda3/etc/profile.d/conda.sh

CONDA_ENV="shotgun_assembly"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 — DEPENDENCY CHECK
# ─────────────────────────────────────────────────────────────────────────────
echo "[CHECK] Verifying tools in conda environment: $CONDA_ENV"

for tool in megahit quast.py; do
    if ! conda run -n "$CONDA_ENV" which "$tool" &>/dev/null; then
        echo "[ERROR] '$tool' not found in conda environment '$CONDA_ENV'"
        echo "        Fix: conda install -n $CONDA_ENV -c bioconda $tool"
        exit 1
    else
        VERSION=$(conda run -n "$CONDA_ENV" "$tool" --version 2>&1 | head -n1 || true)
        echo "[OK]    $tool — $VERSION"
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4 — PATH DEFINITIONS
# ─────────────────────────────────────────────────────────────────────────────

# Main project folder on E drive
PROJECT=/mnt/e/kshiteeja/shotgun_project

# Clean reads stay on E drive
CLEAN=$PROJECT/data/clean/$SAMPLE

# Final results will be saved to E drive
FINAL_ASSEMBLY=$PROJECT/results/assembly/$SAMPLE
FINAL_LOGS=$PROJECT/logs

# Temporary MEGAHIT/QUAST working folder inside WSL Linux filesystem
# Your WSL ext4.vhdx is stored on D drive, but inside Ubuntu this appears as /home.
WORK_PROJECT=/home/scccs1/kshiteeja/shotgun_project
WORK_ASSEMBLY=$WORK_PROJECT/results/assembly/$SAMPLE
WORK_LOGS=$WORK_PROJECT/logs

# Create required parent folders
mkdir -p "$FINAL_ASSEMBLY"
mkdir -p "$FINAL_LOGS"
mkdir -p "$WORK_ASSEMBLY"
mkdir -p "$WORK_LOGS"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 5 — INPUT FILE CHECK
# ─────────────────────────────────────────────────────────────────────────────
R1=$CLEAN/${SAMPLE}_1.clean.fastq.gz
R2=$CLEAN/${SAMPLE}_2.clean.fastq.gz

echo "[CHECK] Verifying clean input reads..."

if [ ! -f "$R1" ]; then
    echo "[ERROR] Missing clean R1: $R1"
    echo "        Run script 01 first: bash scripts/01_read_qc.sh $SAMPLE"
    exit 1
fi

if [ ! -f "$R2" ]; then
    echo "[ERROR] Missing clean R2: $R2"
    echo "        Run script 01 first: bash scripts/01_read_qc.sh $SAMPLE"
    exit 1
fi

R1_SIZE=$(du -sh "$R1" | cut -f1)
R2_SIZE=$(du -sh "$R2" | cut -f1)

echo "[OK]    R1: $R1 ($R1_SIZE)"
echo "[OK]    R2: $R2 ($R2_SIZE)"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 6 — OUTPUT + LOG DEFINITIONS
# ─────────────────────────────────────────────────────────────────────────────

# Working outputs inside WSL
MEGAHIT_OUT=$WORK_ASSEMBLY/megahit_out
CONTIGS_WORK=$MEGAHIT_OUT/final.contigs.fa
QUAST_WORK=$WORK_ASSEMBLY/quast
LOG=$WORK_LOGS/${SAMPLE}_02_assembly.log

# Final outputs on E drive
CONTIGS_FINAL=$FINAL_ASSEMBLY/final.contigs.fa
QUAST_FINAL=$FINAL_ASSEMBLY/quast
FINAL_LOG=$FINAL_LOGS/${SAMPLE}_02_assembly_SUCCESS.log

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 7 — THREAD + MEMORY SETTINGS
# ─────────────────────────────────────────────────────────────────────────────
THREADS=16

# Physical RAM : 96GB
# WSL usable   : ~73GB depending on system overhead
# MEGAHIT set  : 60GB to leave safety headroom
MEMORY=60000000000

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 8 — RESUME LOGIC
# ─────────────────────────────────────────────────────────────────────────────

# If final E-drive outputs are already complete, skip everything
if [ -s "$CONTIGS_FINAL" ] && [ -s "$QUAST_FINAL/report.txt" ]; then
    echo ""
    echo "[SKIP] Assembly and QUAST already complete on E drive for sample: $SAMPLE"
    echo "       Final contigs: $CONTIGS_FINAL"
    echo "       QUAST report : $QUAST_FINAL/report.txt"
    echo "       Delete these outputs if you want to force rerun."
    echo ""
    exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 9 — LOG FILE INITIALISATION
# ─────────────────────────────────────────────────────────────────────────────
{
    echo "============================================="
    echo " Script : 02_assembly.sh"
    echo " Sample : $SAMPLE"
    echo " Started: $(date '+%Y-%m-%d %H:%M:%S')"
    echo " Threads: $THREADS"
    echo " Memory : $MEMORY bytes (60GB)"
    echo " R1     : $R1"
    echo " R2     : $R2"
    echo " Work assembly folder : $WORK_ASSEMBLY"
    echo " Final assembly folder: $FINAL_ASSEMBLY"
    echo "============================================="
} > "$LOG"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 10 — MEGAHIT ASSEMBLY
# ─────────────────────────────────────────────────────────────────────────────

if [ -s "$CONTIGS_WORK" ]; then
    log "[SKIP] MEGAHIT already completed in WSL work folder."
    log "       Found: $CONTIGS_WORK"
else
    log "STEP 1/4 — MEGAHIT: de novo metagenomic assembly"
    log "Parameters: min-contig-len=1000, threads=$THREADS, memory=$MEMORY bytes"
    log "MEGAHIT output/work folder: $MEGAHIT_OUT"

    # MEGAHIT refuses to run if output folder already exists.
    # Remove only incomplete previous MEGAHIT output.
    if [ -d "$MEGAHIT_OUT" ] && [ ! -s "$CONTIGS_WORK" ]; then
        log "[WARN] Found incomplete MEGAHIT directory from a previous failed run."
        log "       Removing: $MEGAHIT_OUT"
        rm -rf "$MEGAHIT_OUT"
    fi

    conda run -n "$CONDA_ENV" megahit \
        -1 "$R1" \
        -2 "$R2" \
        -o "$MEGAHIT_OUT" \
        --min-contig-len 1000 \
        -t "$THREADS" \
        -m "$MEMORY" \
        2>&1 | tee -a "$LOG"

    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
        echo "[ERROR] MEGAHIT failed for sample: $SAMPLE"
        echo "        Check log: $LOG"
        exit 1
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 11 — VERIFY ASSEMBLY OUTPUT
# ─────────────────────────────────────────────────────────────────────────────
log "STEP 2/4 — Verifying assembly output"

if [ ! -f "$CONTIGS_WORK" ]; then
    echo "[ERROR] MEGAHIT finished but final.contigs.fa was not found."
    echo "        Expected: $CONTIGS_WORK"
    exit 1
fi

if [ ! -s "$CONTIGS_WORK" ]; then
    echo "[ERROR] MEGAHIT produced an empty contig file."
    echo "        Expected: $CONTIGS_WORK"
    exit 1
fi

# Show first 3 contig headers for manual verification.
# awk is used instead of grep | head to avoid pipefail broken-pipe errors.
log "Contig headers (first 3):"
awk '/^>/ {print; count++} count==3 {exit}' "$CONTIGS_WORK" | tee -a "$LOG"

# Count total contigs
CONTIG_COUNT=$(grep -c "^>" "$CONTIGS_WORK")
CONTIG_SIZE=$(du -sh "$CONTIGS_WORK" | cut -f1)

log "Total contigs assembled: $CONTIG_COUNT"
log "Contig file size: $CONTIG_SIZE"
log "Working contig file: $CONTIGS_WORK"

if [ "$CONTIG_COUNT" -lt 100 ]; then
    log "[WARN] Very few contigs assembled ($CONTIG_COUNT)."
    log "       Check read quality and sequencing depth."
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 12 — QUAST: ASSEMBLY QUALITY ASSESSMENT
# ─────────────────────────────────────────────────────────────────────────────

if [ -s "$QUAST_WORK/report.txt" ]; then
    log "[SKIP] QUAST already completed in WSL work folder."
    log "       Found: $QUAST_WORK/report.txt"
else
    log "STEP 3/4 — QUAST: assembly quality assessment"

    # Recreate QUAST folder to avoid mixing old and new reports
    rm -rf "$QUAST_WORK"
    mkdir -p "$QUAST_WORK"

    conda run -n "$CONDA_ENV" quast.py \
        "$CONTIGS_WORK" \
        -o "$QUAST_WORK" \
        -t "$THREADS" \
        --min-contig 1000 \
        2>&1 | tee -a "$LOG"

    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
        echo "[ERROR] QUAST failed for sample: $SAMPLE"
        echo "        Check log: $LOG"
        exit 1
    fi
fi

log "QUAST DONE — report written to: $QUAST_WORK/report.txt"

# Print key QUAST metrics directly into log for quick thesis reference
if [ -f "$QUAST_WORK/report.txt" ]; then
    log "Key QUAST metrics:"
    grep -E "# contigs|Largest contig|Total length|GC|N50|L50|N's per 100 kbp" \
        "$QUAST_WORK/report.txt" | tee -a "$LOG" || true
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 13 — COPY FINAL OUTPUTS BACK TO E DRIVE
# ─────────────────────────────────────────────────────────────────────────────
log "STEP 4/4 — Copying final assembly outputs back to E drive"

mkdir -p "$FINAL_ASSEMBLY"
mkdir -p "$FINAL_LOGS"

# Copy final contigs
cp "$CONTIGS_WORK" "$CONTIGS_FINAL"

# Copy QUAST folder
rm -rf "$QUAST_FINAL"
cp -r "$QUAST_WORK" "$QUAST_FINAL"

# Copy successful log
cp "$LOG" "$FINAL_LOG"

log "Copied final contigs to: $CONTIGS_FINAL"
log "Copied QUAST folder to : $QUAST_FINAL"
log "Copied log to          : $FINAL_LOG"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 14 — VERIFY E-DRIVE COPY BEFORE DELETING WSL WORK
# ─────────────────────────────────────────────────────────────────────────────
log "Verifying copied outputs on E drive"

if [ ! -s "$CONTIGS_FINAL" ]; then
    echo "[ERROR] Final contigs were not copied correctly to E drive."
    echo "        Expected: $CONTIGS_FINAL"
    echo "        WSL work folder will NOT be deleted."
    exit 1
fi

if [ ! -s "$QUAST_FINAL/report.txt" ]; then
    echo "[ERROR] QUAST report was not copied correctly to E drive."
    echo "        Expected: $QUAST_FINAL/report.txt"
    echo "        WSL work folder will NOT be deleted."
    exit 1
fi

log "[OK] Final contigs and QUAST report safely copied to E drive"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 15 — DELETE TEMPORARY WSL WORK COPY
# ─────────────────────────────────────────────────────────────────────────────
log "Cleaning temporary WSL assembly folder to save D-drive space"

rm -rf "$WORK_ASSEMBLY"

log "Temporary WSL assembly folder deleted: $WORK_ASSEMBLY"

# Keep the WSL log copy small, or remove it if desired
# The successful log has already been copied to E drive.
rm -f "$LOG"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 16 — FINAL MESSAGE
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=================================================="
echo " Assembly completed successfully for: $SAMPLE"
echo " Final contigs: $CONTIGS_FINAL"
echo " QUAST report : $QUAST_FINAL/report.txt"
echo " Log file     : $FINAL_LOG"
echo " Finished     : $(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================="
echo ""