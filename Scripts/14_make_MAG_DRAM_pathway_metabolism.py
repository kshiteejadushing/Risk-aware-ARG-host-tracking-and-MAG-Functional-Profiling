#!/usr/bin/env python3
# =============================================================================
# Script : 14_make_MAG_DRAM_pathway_metabolism.py
#
# Purpose:
#   Create final Table 2:
#
#       MAG/bin → GTDB taxonomy → CheckM2 quality → DRAM pathway/metabolism
#
#   This table summarizes metabolic and bioremediation-relevant potential
#   for each CheckM2-good MAG using DRAM output.
#
# =============================================================================
#
# INPUTS
# -----------------------------------------------------------------------------
#
# INPUT 1 — DRAM annotation table from Script 11
#
#   results/dram/<SAMPLE_ID>/annotation/annotations.tsv
#
#
# INPUT 2 — DRAM distill output folder from Script 12
#
#   results/dram/<SAMPLE_ID>/distill/
#
#   This script scans this folder and records available distill files.
#   Because DRAM distill filenames can vary by version, the main feature table
#   is built primarily from annotations.tsv in a reproducible way.
#
#
# INPUT 3 — GTDB-Tk taxonomy summary from Script 10
#
#   results/gtdbtk/<SAMPLE_ID>/<SAMPLE_ID>_GTDBTK_taxonomy_summary.tsv
#
#
# INPUT 4 — CheckM2 good MAG table from Script 09
#
#   results/checkm2/<SAMPLE_ID>/<SAMPLE_ID>_checkm2_good_MAGs.tsv
#
#
# OUTPUTS
# -----------------------------------------------------------------------------
#
# Output folder:
#
#   results/final_tables/<SAMPLE_ID>/
#
# Output files:
#
#   02_MAG_DRAM_pathway_metabolism.tsv
#   02_MAG_DRAM_pathway_metabolism.xlsx
#
#
# Excel sheets:
#
#   README
#   Table2_MAG_pathway_metabolism
#   Summary_by_MAG
#   Summary_by_category
#   DRAM_distill_files
#
#
# USAGE
# -----------------------------------------------------------------------------
#
#   cd /mnt/e/kshiteeja/shotgun_project
#
#   python scripts/14_make_MAG_DRAM_pathway_metabolism.py \
#       --sample ERR12510647
#
#
# NOTE
# -----------------------------------------------------------------------------
#
#   This script does NOT score MAGs.
#   Scoring will be done in Script 15 using:
#
#       Table 1: ARG evidence + taxonomy
#       Table 2: DRAM pathway/metabolism
#
# =============================================================================


import argparse
import sys
from pathlib import Path
from collections import defaultdict

import pandas as pd
from openpyxl.styles import Font, Alignment


# =============================================================================
# MESSAGE FUNCTIONS
# =============================================================================

def log(message: str):
    print(f"[INFO] {message}")


def warn(message: str):
    print(f"[WARN] {message}")


def error(message: str):
    print(f"[ERROR] {message}", file=sys.stderr)
    sys.exit(1)


# =============================================================================
# GENERAL HELPERS
# =============================================================================

def normalize_colname(col: str) -> str:
    return str(col).strip().lower().replace(" ", "_").replace("-", "_")


def find_column(df: pd.DataFrame, candidates):
    """
    Flexible column finder.

    Example:
        "user_genome", "User Genome", and "user genome"
    can all be matched.
    """

    normalized_map = {normalize_colname(c): c for c in df.columns}

    for candidate in candidates:
        candidate_norm = normalize_colname(candidate)
        if candidate_norm in normalized_map:
            return normalized_map[candidate_norm]

    return None


def clean_mag_id(value):
    """
    Normalize MAG/bin IDs.

    Examples:
        bin.12
        bin.12.fa
        bin.12.fasta
        bin.12.fna

    all become:
        bin.12
    """

    if pd.isna(value):
        return ""

    value = str(value).strip()

    # If full path was stored, keep only filename.
    value = Path(value).name

    for suffix in [".fa", ".fasta", ".fna"]:
        if value.endswith(suffix):
            value = value[: -len(suffix)]

    return value


def split_multi_value(value):
    """
    Split values that may contain multiple IDs.

    Handles:
        K00001;K00002
        K00001,K00002
        K00001 K00002
    """

    if pd.isna(value):
        return []

    value = str(value).strip()

    if value == "" or value.lower() in ["nan", "none", "na"]:
        return []

    for sep in [";", ",", "|"]:
        value = value.replace(sep, " ")

    parts = [x.strip() for x in value.split() if x.strip()]
    return sorted(set(parts))


# =============================================================================
# GTDB TAXONOMY
# =============================================================================

def parse_gtdb_taxonomy(taxonomy):
    ranks = {
        "domain": "",
        "phylum": "",
        "class": "",
        "order": "",
        "family": "",
        "genus": "",
        "species": "",
    }

    if pd.isna(taxonomy):
        return ranks

    taxonomy = str(taxonomy).strip()

    for part in taxonomy.split(";"):
        part = part.strip()

        if part.startswith("d__"):
            ranks["domain"] = part.replace("d__", "", 1)
        elif part.startswith("p__"):
            ranks["phylum"] = part.replace("p__", "", 1)
        elif part.startswith("c__"):
            ranks["class"] = part.replace("c__", "", 1)
        elif part.startswith("o__"):
            ranks["order"] = part.replace("o__", "", 1)
        elif part.startswith("f__"):
            ranks["family"] = part.replace("f__", "", 1)
        elif part.startswith("g__"):
            ranks["genus"] = part.replace("g__", "", 1)
        elif part.startswith("s__"):
            ranks["species"] = part.replace("s__", "", 1)

    return ranks


def read_gtdb_taxonomy(gtdb_path: Path):
    if not gtdb_path.exists():
        error(
            "GTDB-Tk taxonomy summary not found:\n"
            f"  {gtdb_path}\n\n"
            "Run Script 10 before Script 14."
        )

    df = pd.read_csv(gtdb_path, sep="\t", dtype=str)

    col_genome = find_column(df, ["user_genome", "genome", "Genome", "User Genome"])
    col_taxonomy = find_column(df, ["classification", "Classification", "gtdb_taxonomy"])

    if col_genome is None or col_taxonomy is None:
        error(
            "GTDB summary must contain user_genome and classification columns.\n\n"
            "Available columns:\n"
            + "\n".join(f"  - {x}" for x in df.columns)
        )

    records = []

    for _, row in df.iterrows():
        mag_id = clean_mag_id(row[col_genome])
        taxonomy = row[col_taxonomy]
        ranks = parse_gtdb_taxonomy(taxonomy)

        records.append({
            "mag_id": mag_id,
            "gtdb_taxonomy": taxonomy,
            "domain": ranks["domain"],
            "phylum": ranks["phylum"],
            "class": ranks["class"],
            "order": ranks["order"],
            "family": ranks["family"],
            "genus": ranks["genus"],
            "species": ranks["species"],
        })

    out = pd.DataFrame(records)
    return out.drop_duplicates(subset=["mag_id"])


# =============================================================================
# CHECKM2 QUALITY
# =============================================================================

def read_checkm2_quality(checkm2_path: Path):
    if not checkm2_path.exists():
        error(
            "CheckM2 good MAG table not found:\n"
            f"  {checkm2_path}\n\n"
            "Run Script 09 before Script 14."
        )

    df = pd.read_csv(checkm2_path, sep="\t", dtype=str)

    col_name = find_column(df, ["Name", "name", "bin_id", "Bin_ID", "Genome", "genome"])
    col_completeness = find_column(df, ["Completeness", "completeness"])
    col_contamination = find_column(df, ["Contamination", "contamination"])

    if col_name is None or col_completeness is None or col_contamination is None:
        error(
            "CheckM2 table must contain MAG name, Completeness, and Contamination.\n\n"
            "Available columns:\n"
            + "\n".join(f"  - {x}" for x in df.columns)
        )

    out = pd.DataFrame()
    out["mag_id"] = df[col_name].apply(clean_mag_id)
    out["completeness"] = df[col_completeness].fillna("")
    out["contamination"] = df[col_contamination].fillna("")
    out["checkm2_quality_set"] = "good_MAGs_75_10"

    return out.drop_duplicates(subset=["mag_id"])


# =============================================================================
# BIOREMEDIATION / METABOLISM CLASSIFICATION
# =============================================================================

def classify_function(text, ko_id="", cazy_id="", merops_id=""):
    """
    Classify DRAM annotation text into broad metabolism/bioremediation categories.

    This is intentionally conservative.
    It does not prove activity.
    It marks potential based on annotation keywords / database hits.
    """

    combined = " ".join([
        str(text) if not pd.isna(text) else "",
        str(ko_id) if not pd.isna(ko_id) else "",
        str(cazy_id) if not pd.isna(cazy_id) else "",
        str(merops_id) if not pd.isna(merops_id) else "",
    ]).lower()

    # Aromatic / xenobiotic degradation
    aromatic_keywords = [
        "aromatic", "benzoate", "benzoyl", "catechol", "protocatechuate",
        "phenol", "toluene", "xylene", "biphenyl", "dioxygenase",
        "monooxygenase", "ring-cleavage", "ring cleavage", "gentisate",
        "homogentisate", "salicylate", "phthalate"
    ]

    # Hydrocarbon degradation
    hydrocarbon_keywords = [
        "alkane", "alkb", "hydrocarbon", "methane monooxygenase",
        "propane", "butane", "rubredoxin", "alcohol dehydrogenase",
        "aldehyde dehydrogenase"
    ]

    # Nitrogen metabolism
    nitrogen_keywords = [
        "nitrogen", "nitrate", "nitrite", "denitrification", "nitrification",
        "nitric oxide reductase", "nitrous oxide reductase",
        "ammonia monooxygenase", "hydroxylamine", "urease",
        "nar", "nap", "nir", "nor", "nos", "amo", "hao", "nrf"
    ]

    # Sulfur metabolism
    sulfur_keywords = [
        "sulfur", "sulphur", "sulfate", "sulphate", "sulfite", "sulphite",
        "sulfide", "sulphide", "thiosulfate", "sulfur oxidation",
        "sulfate reduction", "sox", "dsr", "apr"
    ]

    # Metal resistance / transformation
    metal_keywords = [
        "metal", "arsenic", "arsenate", "arsenite", "mercury", "mercuric",
        "cadmium", "chromate", "chromium", "copper", "cobalt", "nickel",
        "zinc", "lead", "silver", "tellurite", "selenate", "selenite",
        "efflux", "resistance-nodulation", "heavy metal"
    ]

    # Stress response
    stress_keywords = [
        "oxidative stress", "superoxide", "catalase", "peroxidase",
        "glutathione", "thioredoxin", "heat shock", "cold shock",
        "dna repair", "osmotic stress"
    ]

    # Transporters
    transporter_keywords = [
        "transporter", "abc transporter", "mfs transporter",
        "efflux pump", "permease", "antiporter", "symporter"
    ]

    if any(k in combined for k in aromatic_keywords):
        return (
            "aromatic_xenobiotic_degradation",
            "aromatic compound / xenobiotic degradation-related gene",
            "high"
        )

    if any(k in combined for k in hydrocarbon_keywords):
        return (
            "hydrocarbon_degradation",
            "hydrocarbon degradation-related gene",
            "high"
        )

    if any(k in combined for k in nitrogen_keywords):
        return (
            "nitrogen_metabolism",
            "nitrogen cycling / nitrogen transformation",
            "medium"
        )

    if any(k in combined for k in sulfur_keywords):
        return (
            "sulfur_metabolism",
            "sulfur cycling / sulfur transformation",
            "medium"
        )

    if any(k in combined for k in metal_keywords):
        return (
            "metal_resistance_or_transformation",
            "metal resistance / metal stress adaptation",
            "medium"
        )

    if str(cazy_id).strip() not in ["", "nan", "None"]:
        return (
            "carbohydrate_active_enzymes",
            "CAZyme-associated carbon/polymer degradation",
            "medium"
        )

    if str(merops_id).strip() not in ["", "nan", "None"]:
        return (
            "peptidase_protein_degradation",
            "MEROPS peptidase/protein degradation",
            "low"
        )

    if any(k in combined for k in stress_keywords):
        return (
            "stress_response",
            "stress tolerance / survival potential",
            "low"
        )

    if any(k in combined for k in transporter_keywords):
        return (
            "transporters",
            "transport or efflux-related function",
            "low"
        )

    return ("other_metabolism", "general metabolic function", "low")


# =============================================================================
# DRAM ANNOTATION PARSING
# =============================================================================

def read_dram_annotations(annotations_path: Path):
    if not annotations_path.exists():
        error(
            "DRAM annotations.tsv not found:\n"
            f"  {annotations_path}\n\n"
            "Run Script 11 before Script 14."
        )

    try:
        df = pd.read_csv(annotations_path, sep="\t", dtype=str, low_memory=False)
    except Exception as exc:
        error(
            "Could not read DRAM annotations.tsv:\n"
            f"  {annotations_path}\n\n"
            f"Reason:\n  {exc}"
        )

    if df.empty:
        error(f"DRAM annotations.tsv is empty: {annotations_path}")

    return df


def build_dram_feature_table(dram_df: pd.DataFrame, sample: str):
    """
    Convert DRAM annotations.tsv into a MAG-level pathway/metabolism table.

    Output is grouped by:
        MAG + category + pathway + gene/module + KO/PFAM/CAZy/MEROPS
    """

    # DRAM versions can vary, so columns are detected flexibly.
    col_mag = find_column(dram_df, ["fasta", "genome", "mag_id", "bin_id"])
    col_scaffold = find_column(dram_df, ["scaffold", "contig", "contig_id"])
    col_gene = find_column(dram_df, ["gene_id", "gene", "query_id", "orf_id"])
    col_product = find_column(dram_df, ["product", "gene_product", "description", "kegg_hit", "kofam_hit"])
    col_kegg = find_column(dram_df, ["kegg_id", "ko_id", "kofam_id", "kegg", "ko"])
    col_pfam = find_column(dram_df, ["pfam_hits", "pfam_id", "pfam"])
    col_cazy = find_column(dram_df, ["cazy_hits", "cazy_id", "cazy"])
    col_merops = find_column(dram_df, ["merops_id", "merops_hits", "merops"])
    col_module = find_column(dram_df, ["module", "module_id", "module_name"])

    if col_mag is None:
        error(
            "Could not find MAG/bin column in DRAM annotations.tsv.\n\n"
            "Expected one of:\n"
            "  fasta, genome, mag_id, bin_id\n\n"
            "Available columns:\n"
            + "\n".join(f"  - {x}" for x in dram_df.columns)
        )

    records = []

    for _, row in dram_df.iterrows():

        mag_id = clean_mag_id(row[col_mag])

        if mag_id == "":
            continue

        contig_id = row[col_scaffold] if col_scaffold else ""
        gene_id = row[col_gene] if col_gene else ""
        product = row[col_product] if col_product else ""

        ko_values = split_multi_value(row[col_kegg]) if col_kegg else [""]
        pfam_values = split_multi_value(row[col_pfam]) if col_pfam else [""]
        cazy_values = split_multi_value(row[col_cazy]) if col_cazy else [""]
        merops_values = split_multi_value(row[col_merops]) if col_merops else [""]

        # Keep at least one value so records are still created.
        if not ko_values:
            ko_values = [""]
        if not pfam_values:
            pfam_values = [""]
        if not cazy_values:
            cazy_values = [""]
        if not merops_values:
            merops_values = [""]

        module_value = row[col_module] if col_module else ""

        # To avoid exploding combinations too much, prioritize KO and product.
        # PFAM/CAZy/MEROPS are stored as semicolon-joined support fields.
        ko_joined = ";".join(ko_values)
        pfam_joined = ";".join(pfam_values)
        cazy_joined = ";".join(cazy_values)
        merops_joined = ";".join(merops_values)

        classification_text = " ".join([
            str(product),
            str(module_value),
            ko_joined,
            pfam_joined,
            cazy_joined,
            merops_joined,
        ])

        pathway_category, pathway_name, relevance = classify_function(
            classification_text,
            ko_id=ko_joined,
            cazy_id=cazy_joined,
            merops_id=merops_joined
        )

        # Keep metabolism/bioremediation-relevant categories.
        # General "other_metabolism" is not very useful for final scoring,
        # but still included so Table 2 is complete.
        records.append({
            "sample_id": sample,
            "mag_id": mag_id,
            "dram_gene_id": gene_id,
            "dram_contig_id": contig_id,
            "pathway_category": pathway_category,
            "pathway_name": pathway_name,
            "gene_or_module": product if str(product).strip() else module_value,
            "ko_id": ko_joined,
            "pfam_id": pfam_joined,
            "cazy_id": cazy_joined,
            "merops_id": merops_joined,
            "detected_gene_count": 1,
            "presence_status": "present",
            "bioremediation_relevance": relevance,
            "evidence_source": "DRAM_annotations.tsv",
        })

    if not records:
        warn("No DRAM annotation records were converted into Table 2 rows.")
        return pd.DataFrame()

    feature_df = pd.DataFrame(records)

    # Group repeated features per MAG.
    grouped = (
        feature_df
        .groupby(
            [
                "sample_id",
                "mag_id",
                "pathway_category",
                "pathway_name",
                "gene_or_module",
                "ko_id",
                "pfam_id",
                "cazy_id",
                "merops_id",
                "presence_status",
                "bioremediation_relevance",
                "evidence_source",
            ],
            dropna=False
        )
        .agg(
            detected_gene_count=("detected_gene_count", "sum"),
            dram_gene_ids=("dram_gene_id", lambda x: ";".join(sorted(set(map(str, x))))),
            dram_contig_ids=("dram_contig_id", lambda x: ";".join(sorted(set(map(str, x)))))
        )
        .reset_index()
    )

    return grouped


# =============================================================================
# DRAM DISTILL FILE SCAN
# =============================================================================

def scan_distill_files(distill_dir: Path):
    """
    Record which DRAM distill files are available.

    DRAM distill output names can vary between versions.
    This manifest is included in Excel for transparency.
    """

    records = []

    if not distill_dir.exists():
        warn(f"DRAM distill folder not found: {distill_dir}")
        return pd.DataFrame(columns=["file_name", "file_path", "file_size_bytes"])

    files = []
    for pattern in ["*.tsv", "*.txt", "*.csv", "*.xlsx"]:
        files.extend(distill_dir.rglob(pattern))

    files = sorted(files)

    for file in files:
        try:
            size = file.stat().st_size
        except Exception:
            size = ""

        records.append({
            "file_name": file.name,
            "file_path": str(file),
            "file_size_bytes": size,
        })

    if not records:
        warn(f"No readable DRAM distill files found in: {distill_dir}")

    return pd.DataFrame(records)


# =============================================================================
# EXCEL WRITER
# =============================================================================

def write_excel(output_xlsx, table_df, summary_mag, summary_category, distill_manifest, metadata):
    with pd.ExcelWriter(output_xlsx, engine="openpyxl") as writer:

        readme_df = pd.DataFrame(
            [{"field": key, "value": value} for key, value in metadata.items()]
        )

        readme_df.to_excel(writer, sheet_name="README", index=False)
        table_df.to_excel(writer, sheet_name="Table2_MAG_pathway_metabolism", index=False)
        summary_mag.to_excel(writer, sheet_name="Summary_by_MAG", index=False)
        summary_category.to_excel(writer, sheet_name="Summary_by_category", index=False)
        distill_manifest.to_excel(writer, sheet_name="DRAM_distill_files", index=False)

        for sheet_name in writer.sheets:
            ws = writer.sheets[sheet_name]

            ws.freeze_panes = "A2"
            ws.auto_filter.ref = ws.dimensions

            for cell in ws[1]:
                cell.font = Font(bold=True)
                cell.alignment = Alignment(wrap_text=True, vertical="top")

            for row in ws.iter_rows():
                for cell in row:
                    cell.alignment = Alignment(wrap_text=True, vertical="top")

            for col_cells in ws.columns:
                col_letter = col_cells[0].column_letter
                max_len = 0

                for cell in col_cells:
                    if cell.value is not None:
                        max_len = max(max_len, len(str(cell.value)))

                ws.column_dimensions[col_letter].width = min(max(max_len + 2, 10), 60)


# =============================================================================
# MAIN
# =============================================================================

def main():

    parser = argparse.ArgumentParser(
        description="Create Table 2: MAG/bin → DRAM pathway/metabolism table."
    )

    parser.add_argument(
        "--sample",
        required=True,
        help="Sample ID, example: ERR12510647"
    )

    parser.add_argument(
        "--project",
        default="/mnt/e/kshiteeja/shotgun_project",
        help="Main project folder"
    )

    parser.add_argument(
        "--annotations",
        default=None,
        help="Optional custom DRAM annotations.tsv path"
    )

    parser.add_argument(
        "--distill-dir",
        default=None,
        help="Optional custom DRAM distill folder"
    )

    parser.add_argument(
        "--gtdb",
        default=None,
        help="Optional custom GTDB-Tk taxonomy summary"
    )

    parser.add_argument(
        "--checkm2",
        default=None,
        help="Optional custom CheckM2 good MAG table"
    )

    args = parser.parse_args()

    sample = args.sample
    project = Path(args.project)

    # =========================================================================
    # PATH DEFINITIONS
    # =========================================================================

    annotations_path = (
        Path(args.annotations)
        if args.annotations
        else project / "results" / "dram" / sample / "annotation" / "annotations.tsv"
    )

    distill_dir = (
        Path(args.distill_dir)
        if args.distill_dir
        else project / "results" / "dram" / sample / "distill"
    )

    gtdb_path = (
        Path(args.gtdb)
        if args.gtdb
        else project / "results" / "gtdbtk" / sample / f"{sample}_GTDBTK_taxonomy_summary.tsv"
    )

    checkm2_path = (
        Path(args.checkm2)
        if args.checkm2
        else project / "results" / "checkm2" / sample / f"{sample}_checkm2_good_MAGs.tsv"
    )

    final_dir = project / "results" / "final_tables" / sample
    final_dir.mkdir(parents=True, exist_ok=True)

    output_tsv = final_dir / "02_MAG_DRAM_pathway_metabolism.tsv"
    output_xlsx = final_dir / "02_MAG_DRAM_pathway_metabolism.xlsx"

    # =========================================================================
    # PRINT INPUT / OUTPUT SUMMARY
    # =========================================================================

    print("")
    print("======================================================")
    print("  Step 14: Table 2 MAG → DRAM pathway/metabolism")
    print("======================================================")
    print(f"  Sample ID                  : {sample}")
    print(f"  Project folder             : {project}")
    print("")
    print("  INPUTS")
    print("  ----------------------------------------------------")
    print(f"  INPUT 1 DRAM annotations   : {annotations_path}")
    print(f"  INPUT 2 DRAM distill dir   : {distill_dir}")
    print(f"  INPUT 3 GTDB taxonomy      : {gtdb_path}")
    print(f"  INPUT 4 CheckM2 quality    : {checkm2_path}")
    print("")
    print("  OUTPUTS")
    print("  ----------------------------------------------------")
    print(f"  OUTPUT 1 final TSV         : {output_tsv}")
    print(f"  OUTPUT 2 final Excel       : {output_xlsx}")
    print("======================================================")
    print("")

    # =========================================================================
    # READ INPUTS
    # =========================================================================

    log("Reading DRAM annotations.tsv")
    dram_df = read_dram_annotations(annotations_path)
    log(f"DRAM annotation rows loaded: {len(dram_df)}")

    log("Reading GTDB-Tk taxonomy")
    gtdb_df = read_gtdb_taxonomy(gtdb_path)
    log(f"GTDB MAGs loaded: {len(gtdb_df)}")

    log("Reading CheckM2 quality table")
    checkm2_df = read_checkm2_quality(checkm2_path)
    log(f"CheckM2 good MAGs loaded: {len(checkm2_df)}")

    log("Scanning DRAM distill folder")
    distill_manifest = scan_distill_files(distill_dir)
    log(f"DRAM distill files recorded: {len(distill_manifest)}")

    # =========================================================================
    # BUILD TABLE 2 FROM DRAM ANNOTATIONS
    # =========================================================================

    log("Building MAG-level DRAM pathway/metabolism table")

    table2 = build_dram_feature_table(dram_df, sample)

    if table2.empty:
        warn("Table 2 is empty after DRAM parsing.")
        table2 = pd.DataFrame(
            columns=[
                "sample_id",
                "mag_id",
                "pathway_category",
                "pathway_name",
                "gene_or_module",
                "ko_id",
                "pfam_id",
                "cazy_id",
                "merops_id",
                "detected_gene_count",
                "presence_status",
                "bioremediation_relevance",
                "evidence_source",
                "dram_gene_ids",
                "dram_contig_ids",
            ]
        )

    # =========================================================================
    # ADD GTDB TAXONOMY AND CHECKM2 QUALITY
    # =========================================================================

    log("Adding GTDB taxonomy and CheckM2 quality")

    table2 = table2.merge(gtdb_df, how="left", on="mag_id")
    table2 = table2.merge(checkm2_df, how="left", on="mag_id")

    # Fill missing values.
    taxonomy_cols = [
        "gtdb_taxonomy",
        "domain",
        "phylum",
        "class",
        "order",
        "family",
        "genus",
        "species",
    ]

    for col in taxonomy_cols:
        if col not in table2.columns:
            table2[col] = "missing"
        table2[col] = table2[col].fillna("missing")

    for col in ["completeness", "contamination", "checkm2_quality_set"]:
        if col not in table2.columns:
            table2[col] = "missing"
        table2[col] = table2[col].fillna("missing")

    # =========================================================================
    # REORDER COLUMNS
    # =========================================================================

    preferred_cols = [
        "sample_id",
        "mag_id",
        "gtdb_taxonomy",
        "domain",
        "phylum",
        "class",
        "order",
        "family",
        "genus",
        "species",
        "completeness",
        "contamination",
        "checkm2_quality_set",
        "pathway_category",
        "pathway_name",
        "gene_or_module",
        "ko_id",
        "pfam_id",
        "cazy_id",
        "merops_id",
        "detected_gene_count",
        "presence_status",
        "bioremediation_relevance",
        "evidence_source",
        "dram_gene_ids",
        "dram_contig_ids",
    ]

    existing_preferred = [col for col in preferred_cols if col in table2.columns]
    remaining = [col for col in table2.columns if col not in existing_preferred]

    table2 = table2[existing_preferred + remaining]

    # Sort for readability.
    sort_cols = [
        col for col in
        ["mag_id", "pathway_category", "bioremediation_relevance", "pathway_name"]
        if col in table2.columns
    ]

    if sort_cols:
        table2 = table2.sort_values(by=sort_cols)

    # =========================================================================
    # SAVE TSV
    # =========================================================================

    table2.to_csv(output_tsv, sep="\t", index=False)

    # =========================================================================
    # SUMMARY TABLES
    # =========================================================================

    if not table2.empty:
        summary_mag = (
            table2
            .groupby(
                ["mag_id", "gtdb_taxonomy", "genus", "species", "completeness", "contamination"],
                dropna=False
            )
            .agg(
                pathway_category_count=("pathway_category", lambda x: len(set(map(str, x)))),
                total_detected_gene_count=("detected_gene_count", lambda x: pd.to_numeric(x, errors="coerce").fillna(0).sum()),
                pathway_categories=("pathway_category", lambda x: "; ".join(sorted(set(map(str, x))))),
                pathway_names=("pathway_name", lambda x: "; ".join(sorted(set(map(str, x))))),
                bioremediation_relevance=("bioremediation_relevance", lambda x: "; ".join(sorted(set(map(str, x)))))
            )
            .reset_index()
        )

        summary_category = (
            table2
            .groupby(["pathway_category", "pathway_name", "bioremediation_relevance"], dropna=False)
            .agg(
                mag_count=("mag_id", lambda x: len(set(map(str, x)))),
                total_detected_gene_count=("detected_gene_count", lambda x: pd.to_numeric(x, errors="coerce").fillna(0).sum()),
                mags=("mag_id", lambda x: "; ".join(sorted(set(map(str, x)))))
            )
            .reset_index()
        )
    else:
        summary_mag = pd.DataFrame()
        summary_category = pd.DataFrame()

    metadata = {
        "sample_id": sample,
        "input_DRAM_annotations": str(annotations_path),
        "input_DRAM_distill_folder": str(distill_dir),
        "input_GTDB_taxonomy": str(gtdb_path),
        "input_CheckM2_quality": str(checkm2_path),
        "output_TSV": str(output_tsv),
        "output_Excel": str(output_xlsx),
        "total_table2_rows": len(table2),
        "unique_MAGs_in_table2": table2["mag_id"].nunique() if "mag_id" in table2.columns else 0,
        "note_1": "This table summarizes MAG-level DRAM pathway/metabolism potential.",
        "note_2": "Bioremediation relevance is inferred from DRAM annotations using conservative keyword/category rules.",
        "note_3": "This table does not prove activity; it represents genomic potential.",
        "note_4": "Final scoring will be performed in Script 15 using Table 1 and Table 2.",
    }

    # =========================================================================
    # SAVE EXCEL
    # =========================================================================

    write_excel(
        output_xlsx=output_xlsx,
        table_df=table2,
        summary_mag=summary_mag,
        summary_category=summary_category,
        distill_manifest=distill_manifest,
        metadata=metadata
    )

    # =========================================================================
    # FINAL SUMMARY
    # =========================================================================

    print("")
    print("======================================================")
    print(f"  Step 14 COMPLETE — {sample}")
    print("======================================================")
    print("")
    print("  INPUTS USED")
    print("  ----------------------------------------------------")
    print(f"  DRAM annotations           : {annotations_path}")
    print(f"  DRAM distill folder        : {distill_dir}")
    print(f"  GTDB taxonomy              : {gtdb_path}")
    print(f"  CheckM2 quality            : {checkm2_path}")
    print("")
    print("  OUTPUTS CREATED")
    print("  ----------------------------------------------------")
    print(f"  Final TSV table            : {output_tsv}")
    print(f"  Final Excel workbook       : {output_xlsx}")
    print("")
    print("  SUMMARY")
    print("  ----------------------------------------------------")
    print(f"  Table 2 rows               : {len(table2)}")
    print(f"  Unique MAGs in Table 2     : {table2['mag_id'].nunique() if 'mag_id' in table2.columns else 0}")
    print(f"  DRAM distill files found   : {len(distill_manifest)}")
    print("")
    print("  EXCEL SHEETS")
    print("  ----------------------------------------------------")
    print("  README")
    print("  Table2_MAG_pathway_metabolism")
    print("  Summary_by_MAG")
    print("  Summary_by_category")
    print("  DRAM_distill_files")
    print("======================================================")


if __name__ == "__main__":
    main()