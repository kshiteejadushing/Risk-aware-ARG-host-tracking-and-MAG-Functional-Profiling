#!/bin/bash
# =============================================================================
# Script : 03_gene_prediction.sh
# Purpose: Predict protein-coding genes from assembled contigs using Prodigal
#          in metagenome mode (-p meta)
# Usage  : bash scripts/03_gene_prediction.sh <SAMPLE_ID>
# Example: bash scripts/03_gene_prediction.sh ERR12510647
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
    echo "Usage  : bash scripts/03_gene_prediction.sh <SAMPLE_ID>"
    echo "Example: bash scripts/03_gene_prediction.sh ERR12510647"
    echo ""
    exit 1
fi

SAMPLE=$1

echo ""
echo "======================================================"
echo "  Shotgun Metagenomics Pipeline — Step 03: Gene Prediction"
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

if ! conda run -n "$CONDA_ENV" which prodigal &>/dev/null; then
    echo "[ERROR] prodigal not found in conda environment '$CONDA_ENV'"
    echo "        Fix: conda install -n $CONDA_ENV -c bioconda prodigal"
    exit 1
else
    VERSION=$(conda run -n "$CONDA_ENV" prodigal -v 2>&1 | head -n1 || true)
    echo "[OK]    prodigal — $VERSION"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4 — PATH DEFINITIONS
# ─────────────────────────────────────────────────────────────────────────────
PROJECT=/mnt/e/kshiteeja/shotgun_project

ASSEMBLY=$PROJECT/results/assembly/$SAMPLE
GENES=$PROJECT/results/gene_prediction/$SAMPLE
LOGS=$PROJECT/logs

mkdir -p "$GENES" "$LOGS"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 5 — INPUT FILE CHECK
# ─────────────────────────────────────────────────────────────────────────────
# IMPORTANT: Path matches output from 02_assembly.sh — megahit_out subfolder
CONTIGS=$ASSEMBLY/final.contigs.fa

echo "[CHECK] Verifying assembly contigs..."

if [ ! -f "$CONTIGS" ]; then
    echo "[ERROR] Missing contigs file:"
    echo "        $CONTIGS"
    echo "        Run assembly first: bash scripts/02_assembly.sh $SAMPLE"
    exit 1
fi

if [ ! -s "$CONTIGS" ]; then
    echo "[ERROR] Contigs file exists but is empty:"
    echo "        $CONTIGS"
    exit 1
fi

CONTIG_SIZE=$(du -sh "$CONTIGS" | cut -f1)
CONTIG_COUNT=$(grep -c "^>" "$CONTIGS")

echo "[OK]    Contigs file : $CONTIGS"
echo "[OK]    Contig size  : $CONTIG_SIZE"
echo "[OK]    Contig count : $CONTIG_COUNT"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 6 — OUTPUT FILE DEFINITIONS
# ─────────────────────────────────────────────────────────────────────────────
# All files prefixed with sample ID for unambiguous identification in Python/R
PROTEINS=$GENES/${SAMPLE}_proteins.faa      # amino acid sequences → RGI/CARD input
GENES_NUC=$GENES/${SAMPLE}_genes.fna        # nucleotide sequences → coverage analysis
GFF=$GENES/${SAMPLE}_annotations.gff        # gene coordinates → ARG-to-contig linking
LOG=$LOGS/${SAMPLE}_03_gene_prediction.log

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 7 — RESUME LOGIC
# ─────────────────────────────────────────────────────────────────────────────
if [ -s "$PROTEINS" ] && [ -s "$GENES_NUC" ] && [ -s "$GFF" ]; then
    echo ""
    echo "[SKIP] Gene prediction already complete for sample: $SAMPLE"
    echo "       Proteins : $PROTEINS"
    echo "       Genes    : $GENES_NUC"
    echo "       GFF      : $GFF"
    echo "       Delete these files to force rerun."
    echo ""
    exit 0
fi

# Remove partial outputs before rerun to avoid corrupted files
if [ -f "$PROTEINS" ] || [ -f "$GENES_NUC" ] || [ -f "$GFF" ]; then
    echo "[WARN] Partial gene prediction output found. Removing incomplete files."
    rm -f "$PROTEINS" "$GENES_NUC" "$GFF"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 8 — LOG INITIALISATION
# ─────────────────────────────────────────────────────────────────────────────
{
    echo "============================================="
    echo " Script : 03_gene_prediction.sh"
    echo " Sample : $SAMPLE"
    echo " Started: $(date '+%Y-%m-%d %H:%M:%S')"
    echo " Tool   : Prodigal -p meta"
    echo " Input  : $CONTIGS"
    echo " Contigs: $CONTIG_COUNT"
    echo "============================================="
} > "$LOG"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"
}

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 9 — PRODIGAL GENE PREDICTION
# ─────────────────────────────────────────────────────────────────────────────
log "STEP 1/2 — Prodigal: predicting protein-coding genes"
log "Mode    : -p meta (metagenome mode — no training required)"
log "Formats : .faa (proteins), .fna (nucleotides), .gff (coordinates)"

conda run -n "$CONDA_ENV" prodigal \
    -i "$CONTIGS" \
    -a "$PROTEINS" \
    -d "$GENES_NUC" \
    -o "$GFF" \
    -f gff \
    -p meta \
    2>&1 | tee -a "$LOG"

if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo "[ERROR] Prodigal failed for sample: $SAMPLE"
    echo "        Check log: $LOG"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 10 — OUTPUT VALIDATION
# ─────────────────────────────────────────────────────────────────────────────
log "STEP 2/2 — Validating Prodigal outputs"

for outfile in "$PROTEINS" "$GENES_NUC" "$GFF"; do
    if [ ! -s "$outfile" ]; then
        echo "[ERROR] Output file missing or empty: $outfile"
        exit 1
    fi
done

PROTEIN_COUNT=$(grep -c "^>" "$PROTEINS")
GENE_COUNT=$(grep -c "^>" "$GENES_NUC")
GFF_LINES=$(grep -v "^#" "$GFF" | wc -l)

log "Proteins predicted    : $PROTEIN_COUNT"
log "Nucleotide genes      : $GENE_COUNT"
log "GFF annotation lines  : $GFF_LINES"

# Sanity check — counts should match
if [ "$PROTEIN_COUNT" -ne "$GENE_COUNT" ]; then
    log "[WARN] Protein count ($PROTEIN_COUNT) differs from gene count ($GENE_COUNT)"
    log "       This can happen due to partial genes at contig edges — usually normal"
fi

# Warn if suspiciously low gene count
if [ "$PROTEIN_COUNT" -lt 100 ]; then
    log "[WARN] Very few proteins predicted ($PROTEIN_COUNT)"
    log "       Check contig quality and assembly completeness"
fi

# Show first 3 protein headers for manual verification
log "Sample protein headers (first 3):"
awk '/^>/ {print; count++} count==3 {exit}' "$PROTEINS" | tee -a "$LOG"

PROTEINS_SIZE=$(du -sh "$PROTEINS" | cut -f1)
log "Protein file size: $PROTEINS_SIZE"

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
echo "  Step 03 COMPLETE — $SAMPLE"
echo "======================================================"
echo "  Proteins (.faa) : $PROTEINS"
echo "  Genes (.fna)    : $GENES_NUC"
echo "  GFF file        : $GFF"
echo "  Protein count   : $PROTEIN_COUNT"
echo "  Log file        : $LOG"
echo ""
echo "  Next step       : bash scripts/04_cdhit.sh $SAMPLE"
echo "======================================================"