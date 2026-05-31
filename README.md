cd /home/kshiteeja/shotgun_practice

cat > README.md <<'EOF'
# Shotgun Metagenomics Pipeline for ARG Host Tracking and MAG Functional Profiling

This repository contains a reproducible shotgun metagenomics workflow for antimicrobial resistance gene (ARG) detection, ARG host tracking, metagenome-assembled genome (MAG) recovery, taxonomic classification, functional annotation, and integrated risk/bioremediation interpretation.

The pipeline is designed to connect ARG evidence with microbial host context and functional potential.

---

## Project Aim

The aim of this workflow is to analyze shotgun metagenomic data and generate integrated evidence linking:

ARG gene → contig → MAG/bin → taxonomy → metabolic function → risk/bioremediation potential

This is useful for studying antimicrobial resistance, environmental resistomes, microbial hosts carrying ARGs, and the potential role of microbial genomes in pharmaceutical or pollutant degradation.

---

## Workflow Overview

1. Project setup and software check
2. Read quality control
3. Metagenomic assembly
4. Gene prediction
5. Gene/protein clustering
6. ARG detection using RGI/CARD
7. Read preparation for metaWRAP
8. Metagenomic binning
9. Bin refinement
10. MAG quality assessment using CheckM2
11. MAG taxonomic classification using GTDB-Tk
12. MAG functional annotation using DRAM
13. DRAM distillation
14. ARG-contig-bin-taxonomy evidence table generation
15. MAG pathway/metabolism table generation
16. Final MAG risk and bioremediation scoring

---

## Repository Structure

shotgun_practice/
├── README.md
├── .gitignore
├── scripts/
│   ├── 00_check_setup.sh
│   ├── 01_read_qc.sh
│   ├── 02_assembly.sh
│   ├── 03_gene_prediction.sh
│   ├── 04_cdhit.sh
│   ├── 05_rgi_arg_detection.sh
│   ├── 06_prepare_metawrap_reads.sh
│   ├── 07_metawrap_binning.sh
│   ├── 08_bin_refinement.sh
│   ├── 09_checkm2.sh
│   ├── 10_gtdbtk_classify_bins.sh
│   ├── 11_dram_annotate.sh
│   ├── 12_dram_distill.sh
│   ├── 13_make_ARG_gene_contig_bin_taxonomy_evidence.py
│   ├── 14_make_MAG_DRAM_pathway_metabolism.py
│   └── 15_make_MAG_risk_bioremediation_scoring.py
└── Notes/
    └── project notes and methodology documents

Large files such as raw reads, databases, intermediate files, and results are excluded from this repository.

---

## Input Data

The pipeline expects paired-end shotgun metagenomic reads.

Example input format:

sample_id_1.fastq.gz
sample_id_2.fastq.gz

Example:

ERR12510647_1.fastq.gz
ERR12510647_2.fastq.gz

Raw reads are not included in this repository.

---

## Main Output Concept

The final goal is not only to detect ARGs, but to place them into genomic and functional context.

The pipeline aims to answer:

- Which ARGs are present?
- Which contigs carry ARGs?
- Which MAGs/bins contain those contigs?
- What is the likely taxonomy of the ARG-carrying host?
- What metabolic or degradation pathways are present in each MAG?
- Which MAGs may represent higher antimicrobial resistance risk?
- Which MAGs may have useful bioremediation or pharmaceutical degradation potential?

---

## Script Description

| Step | Script | Purpose |
|---|---|---|
| 00 | 00_check_setup.sh | Checks folder structure, conda environments, and required tools |
| 01 | 01_read_qc.sh | Performs read quality control and generates cleaned reads |
| 02 | 02_assembly.sh | Performs metagenomic assembly from cleaned reads |
| 03 | 03_gene_prediction.sh | Predicts genes from assembled contigs |
| 04 | 04_cdhit.sh | Clusters predicted genes/proteins to reduce redundancy |
| 05 | 05_rgi_arg_detection.sh | Detects ARGs using RGI and CARD |
| 06 | 06_prepare_metawrap_reads.sh | Prepares read files for metaWRAP-compatible binning |
| 07 | 07_metawrap_binning.sh | Performs metagenomic binning |
| 08 | 08_bin_refinement.sh | Refines bins using available binner outputs |
| 09 | 09_checkm2.sh | Estimates MAG completeness and contamination |
| 10 | 10_gtdbtk_classify_bins.sh | Assigns MAG taxonomy using GTDB-Tk |
| 11 | 11_dram_annotate.sh | Annotates MAGs using DRAM |
| 12 | 12_dram_distill.sh | Summarizes DRAM annotation into interpretable functional summaries |
| 13 | 13_make_ARG_gene_contig_bin_taxonomy_evidence.py | Creates ARG-to-contig-to-bin-to-taxonomy evidence table |
| 14 | 14_make_MAG_DRAM_pathway_metabolism.py | Creates MAG-to-pathway/metabolism summary table |
| 15 | 15_make_MAG_risk_bioremediation_scoring.py | Generates integrated MAG risk and bioremediation scoring table |

---

## Expected Final Tables

### Table 1: ARG Gene-Contig-Bin-Taxonomy Evidence Table

This table links ARGs to their genomic context.

Example columns:

sample_id
arg_gene_id
arg_name
drug_class
resistance_mechanism
arg_contig_id
arg_start
arg_end
bin_id
binned_status
gtdb_taxonomy

Purpose:

ARG gene is found on contig X.
Contig X belongs to bin/MAG Y.
MAG Y has taxonomy Z.
Therefore, ARG host context can be inferred.

---

### Table 2: MAG-DRAM Pathway/Metabolism Table

This table summarizes the functional and metabolic potential of each MAG.

Example columns:

sample_id
mag_id
gtdb_taxonomy
pathway_category
pathway_name
gene_or_module
ko_id
detected_gene_count
evidence_source

Purpose:

MAG Y contains genes/modules associated with pathway or metabolism X.
This supports interpretation of metabolic or bioremediation potential.

---

### Table 3: Final MAG Risk and Bioremediation Scoring Table

This table integrates ARG burden, taxonomy, MAG quality, and functional potential.

Example columns:

sample_id
mag_id
gtdb_taxonomy
completeness
contamination
arg_count
arg_classes
resistance_mechanisms
bioremediation_pathway_count
pharmaceutical_degradation_relevance
risk_score
bioremediation_score
final_interpretation

Purpose:

Identify MAGs that may be high-risk ARG carriers, useful biodegradation candidates, or both.

---

## General Usage

Each script is designed to be run with a sample ID.

Example:

bash scripts/01_read_qc.sh ERR12510647
bash scripts/02_assembly.sh ERR12510647
bash scripts/03_gene_prediction.sh ERR12510647
bash scripts/04_cdhit.sh ERR12510647
bash scripts/05_rgi_arg_detection.sh ERR12510647
bash scripts/06_prepare_metawrap_reads.sh ERR12510647
bash scripts/07_metawrap_binning.sh ERR12510647
bash scripts/08_bin_refinement.sh ERR12510647
bash scripts/09_checkm2.sh ERR12510647
bash scripts/10_gtdbtk_classify_bins.sh ERR12510647
bash scripts/11_dram_annotate.sh ERR12510647
bash scripts/12_dram_distill.sh ERR12510647
python scripts/13_make_ARG_gene_contig_bin_taxonomy_evidence.py ERR12510647
python scripts/14_make_MAG_DRAM_pathway_metabolism.py ERR12510647
python scripts/15_make_MAG_risk_bioremediation_scoring.py ERR12510647

Before running the workflow, check setup:

bash scripts/00_check_setup.sh

---

## Software and Tools

This pipeline uses commonly used metagenomics tools, including:

- FastQC / MultiQC or equivalent read QC tools
- Trimming tools for read quality control
- MEGAHIT or equivalent metagenomic assembler
- Prodigal or equivalent gene prediction tool
- CD-HIT
- RGI/CARD for ARG detection
- metaWRAP for binning and bin refinement
- CheckM2 for MAG quality assessment
- GTDB-Tk for MAG taxonomic classification
- DRAM for MAG functional annotation and distillation
- Python for final table generation

Exact tool versions and conda environments should be recorded separately for reproducibility.

---

## Data and File Exclusion

The following are intentionally not uploaded to GitHub:

raw_data/
results/
logs/
work_files/
databases/
metawrap_databases/
GTDBTK/
DRAM_data/
checkm2_db/
kraken2/
*.fastq
*.fastq.gz
*.bam
*.sam
*.fasta
*.faa
*.fna
*.dmnd
*.bt2
*.hmm

These files are excluded because they are large, sample-specific, or database-dependent.

---

## Reproducibility Notes

For best reproducibility, users should record:

- Sample accession numbers
- Read source and download links
- Tool versions
- Conda environment names
- Database versions
- CARD database version
- GTDB-Tk database release
- CheckM2 database version
- DRAM database setup details
- Script execution date

---

## Example Research Use Case

This workflow can be applied to wastewater, sewage, environmental, clinical, or other shotgun metagenomic datasets where the goal is to study ARGs and their microbial hosts.

In particular, the workflow is useful for projects focused on:

- Antimicrobial resistance surveillance
- ARG host prediction using MAGs
- Environmental resistome analysis
- MAG-based functional profiling
- Bioremediation potential screening
- Pharmaceutical degradation potential in microbial communities

---

## Important Limitations

MAG-based ARG host assignment is an inference and depends on assembly quality, binning quality, and contig placement.

Important limitations include:

- ARGs on short or unbinned contigs may not be assigned to a host.
- Bins may contain contamination.
- Closely related organisms can be difficult to separate.
- Mobile genetic elements may move ARGs across hosts.
- MAG taxonomy depends on database coverage.
- Functional annotation indicates potential, not experimentally confirmed activity.

Therefore, final interpretations should be treated as computational evidence, not direct experimental proof.

---

## Recommended Citation/Attribution

If this workflow is reused, cite the tools and databases used in the analysis, including CARD/RGI, metaWRAP, CheckM2, GTDB-Tk, DRAM, CD-HIT, and the assembler/gene prediction tools used in the pipeline.

---

## Author

Kshiteeja Dushing

---

## Repository Status

This repository is under active development as part of a shotgun metagenomics project focused on ARG tracking, MAG interpretation, and bioremediation-oriented functional analysis.
EOF
