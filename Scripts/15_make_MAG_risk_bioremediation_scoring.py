#!/usr/bin/env python3
# =============================================================================
# Script : 15_make_MAG_risk_bioremediation_scoring.py
#
# Purpose:
#   Create final Table 3:
#
#       MAG/bin → organism → ARG risk → bioremediation potential → final score
#
#   This script combines:
#
#       Table 1:
#           01_ARG_gene_contig_bin_taxonomy_evidence.tsv
#
#       Table 2:
#           02_MAG_DRAM_pathway_metabolism.tsv
#
#   Final output:
#
#       03_MAG_risk_bioremediation_scoring.tsv
#       03_MAG_risk_bioremediation_scoring.xlsx
#
# =============================================================================
#
# INPUT 1 — Table 1 from Script 13
#
#   results/final_tables/<SAMPLE_ID>/01_ARG_gene_contig_bin_taxonomy_evidence.tsv
#
#   Contains:
#       ARG gene
#       contig
#       bin/MAG
#       GTDB taxonomy
#
#
# INPUT 2 — Table 2 from Script 14
#
#   results/final_tables/<SAMPLE_ID>/02_MAG_DRAM_pathway_metabolism.tsv
#
#   Contains:
#       MAG/bin
#       GTDB taxonomy
#       CheckM2 quality
#       DRAM metabolism/pathway potential
#
#
# OUTPUT — Table 3
#
#   results/final_tables/<SAMPLE_ID>/03_MAG_risk_bioremediation_scoring.tsv
#   results/final_tables/<SAMPLE_ID>/03_MAG_risk_bioremediation_scoring.xlsx
#
#
# EXCEL SHEETS
#
#   README
#   Table3_final_scoring
#   Risky_and_useful_MAGs
#   High_ARG_risk_MAGs
#   Bioremediation_MAGs
#   Low_priority_MAGs
#
#
# USAGE
#
#   cd /mnt/e/kshiteeja/shotgun_project
#
#   python scripts/15_make_MAG_risk_bioremediation_scoring.py \
#       --sample ERR12510647
#
# =============================================================================


import argparse
import sys
from pathlib import Path

import pandas as pd
from openpyxl.styles import Font, Alignment


# =============================================================================
# BASIC FUNCTIONS
# =============================================================================

def log(message: str):
    print(f"[INFO] {message}")


def warn(message: str):
    print(f"[WARN] {message}")


def error(message: str):
    print(f"[ERROR] {message}", file=sys.stderr)
    sys.exit(1)


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
    value = Path(value).name

    for suffix in [".fa", ".fasta", ".fna"]:
        if value.endswith(suffix):
            value = value[: -len(suffix)]

    return value


def unique_join(values):
    """
    Join unique non-empty values using semicolon.
    """

    clean_values = []

    for value in values:
        if pd.isna(value):
            continue

        value = str(value).strip()

        if value == "" or value.lower() in ["nan", "none", "na"]:
            continue

        # Split already-joined values.
        for sep in [";", "|"]:
            value = value.replace(sep, ",")

        for part in value.split(","):
            part = part.strip()
            if part:
                clean_values.append(part)

    clean_values = sorted(set(clean_values))

    if not clean_values:
        return "none"

    return "; ".join(clean_values)


def safe_numeric(value, default=0.0):
    try:
        return float(value)
    except Exception:
        return default


# =============================================================================
# RISK SCORING LOGIC
# =============================================================================

def is_high_risk_arg(arg_name, drug_class, mechanism, family):
    """
    Conservative high-risk ARG flag.

    This does not mean clinically confirmed pathogen risk.
    It means the ARG belongs to categories commonly considered concerning:
        beta-lactam
        carbapenem
        vancomycin/glycopeptide
        colistin/polymyxin
        aminoglycoside
        fluoroquinolone
        multidrug efflux
        mobile/integron-associated names where visible
    """

    text = " ".join([
        str(arg_name),
        str(drug_class),
        str(mechanism),
        str(family),
    ]).lower()

    high_risk_keywords = [
        "carbapenem",
        "beta-lactam",
        "beta_lactam",
        "bla",
        "ndm",
        "kpc",
        "oxa",
        "vim",
        "imp",
        "ctx-m",
        "ctx_m",
        "vancomycin",
        "glycopeptide",
        "van",
        "colistin",
        "polymyxin",
        "mcr",
        "fluoroquinolone",
        "quinolone",
        "qnr",
        "aminoglycoside",
        "aac",
        "aph",
        "ant(",
        "multidrug",
        "mdt",
        "mex",
        "acr",
        "efflux",
        "integron",
        "sul1",
        "sul2",
        "tet",
    ]

    return any(keyword in text for keyword in high_risk_keywords)


def calculate_arg_risk_score(arg_count, high_risk_arg_count, drug_class_count):
    """
    ARG risk score from 0 to 5.

    Score meaning:
        0 = no ARG detected in MAG
        1 = low ARG burden
        2 = moderate ARG burden
        3 = high ARG diversity or at least one high-risk ARG
        4 = multiple high-risk ARGs
        5 = very high ARG burden and multiple high-risk ARGs
    """

    arg_count = int(arg_count)
    high_risk_arg_count = int(high_risk_arg_count)
    drug_class_count = int(drug_class_count)

    if arg_count == 0:
        return 0

    score = 1

    if arg_count >= 2:
        score += 1

    if drug_class_count >= 2:
        score += 1

    if high_risk_arg_count >= 1:
        score += 1

    if high_risk_arg_count >= 3 or arg_count >= 5:
        score += 1

    return min(score, 5)


def calculate_bioremediation_score(high_relevance_count, medium_relevance_count, category_count):
    """
    Bioremediation potential score from 0 to 5.

    Score meaning:
        0 = no relevant DRAM features
        1 = weak/general potential
        2 = some medium-relevance features
        3 = strong pathway diversity or high-relevance features
        4 = multiple high-relevance features
        5 = high and diverse bioremediation potential
    """

    high_relevance_count = int(high_relevance_count)
    medium_relevance_count = int(medium_relevance_count)
    category_count = int(category_count)

    if high_relevance_count == 0 and medium_relevance_count == 0:
        return 0

    score = 1

    if medium_relevance_count >= 2:
        score += 1

    if high_relevance_count >= 1:
        score += 1

    if category_count >= 2:
        score += 1

    if high_relevance_count >= 3 or category_count >= 4:
        score += 1

    return min(score, 5)


def assign_priority_group(arg_risk_score, bioremediation_score):
    """
    Assign final MAG group.
    """

    if arg_risk_score >= 3 and bioremediation_score >= 3:
        return "priority_watchlist_risky_and_bioremediation_relevant"

    if arg_risk_score >= 3 and bioremediation_score < 3:
        return "high_ARG_risk_only"

    if arg_risk_score < 3 and bioremediation_score >= 3:
        return "bioremediation_relevant_low_ARG_risk"

    if arg_risk_score > 0 and bioremediation_score > 0:
        return "moderate_mixed_potential"

    if arg_risk_score > 0 and bioremediation_score == 0:
        return "ARG_present_low_bioremediation_signal"

    if arg_risk_score == 0 and bioremediation_score > 0:
        return "bioremediation_signal_no_ARG_detected"

    return "low_priority_no_ARG_no_bioremediation_signal"


def make_final_interpretation(row):
    """
    Human-readable interpretation for each MAG.
    """

    mag = row["mag_id"]
    genus = row.get("genus", "missing")
    species = row.get("species", "missing")
    arg_count = row["arg_count"]
    risk = row["arg_risk_score"]
    bio = row["bioremediation_score"]
    group = row["priority_group"]

    organism = f"{genus} {species}".strip()
    if organism == "" or organism.lower() in ["missing missing", "none none"]:
        organism = "unresolved taxonomy"

    if group == "priority_watchlist_risky_and_bioremediation_relevant":
        return (
            f"{mag} ({organism}) carries ARGs and also has DRAM-supported "
            f"bioremediation-relevant metabolic potential. This MAG should be "
            f"treated as a priority watchlist organism: useful potential but ARG-associated risk."
        )

    if group == "high_ARG_risk_only":
        return (
            f"{mag} ({organism}) shows elevated ARG risk but limited DRAM-supported "
            f"bioremediation potential. This MAG is mainly a resistance-risk signal."
        )

    if group == "bioremediation_relevant_low_ARG_risk":
        return (
            f"{mag} ({organism}) has DRAM-supported bioremediation-relevant potential "
            f"with low ARG burden. This MAG may be a useful low-risk candidate."
        )

    if group == "moderate_mixed_potential":
        return (
            f"{mag} ({organism}) has both ARG signal and some bioremediation-relevant "
            f"features, but not at the highest priority level."
        )

    if group == "ARG_present_low_bioremediation_signal":
        return (
            f"{mag} ({organism}) carries ARGs but shows weak or no bioremediation-relevant "
            f"DRAM signal in this table."
        )

    if group == "bioremediation_signal_no_ARG_detected":
        return (
            f"{mag} ({organism}) has bioremediation-relevant DRAM features and no ARGs "
            f"linked through the final good-MAG evidence table."
        )

    return (
        f"{mag} ({organism}) has no linked ARGs and no strong bioremediation-relevant "
        f"signal based on the current scoring rules."
    )


# =============================================================================
# TABLE READERS
# =============================================================================

def read_table(path: Path, label: str):
    if not path.exists():
        error(f"{label} not found:\n  {path}")

    try:
        df = pd.read_csv(path, sep="\t", dtype=str)
    except Exception as exc:
        error(f"Could not read {label}:\n  {path}\n\nReason:\n  {exc}")

    return df


# =============================================================================
# SUMMARIZE TABLE 1: ARG RISK BY MAG
# =============================================================================

def summarize_arg_table(table1: pd.DataFrame):
    """
    Convert Table 1 into one row per MAG/bin with ARG summary.
    """

    required = ["bin_id", "binned_status", "arg_gene_id", "arg_name", "drug_class"]

    missing = [col for col in required if col not in table1.columns]

    if missing:
        error(
            "Table 1 is missing required columns:\n"
            + "\n".join(f"  - {x}" for x in missing)
        )

    # Keep only ARGs linked to good MAGs.
    linked = table1[table1["binned_status"] == "binned_good_MAG"].copy()

    if linked.empty:
        warn("No ARGs linked to good MAGs in Table 1.")

        return pd.DataFrame(
            columns=[
                "mag_id",
                "arg_count",
                "arg_names",
                "drug_classes",
                "resistance_mechanisms",
                "amr_gene_families",
                "high_risk_arg_count",
                "high_risk_arg_names",
                "drug_class_count",
            ]
        )

    linked["mag_id"] = linked["bin_id"].apply(clean_mag_id)

    for col in ["resistance_mechanism", "amr_gene_family", "genus", "species", "gtdb_taxonomy"]:
        if col not in linked.columns:
            linked[col] = ""

    linked["high_risk_flag"] = linked.apply(
        lambda row: is_high_risk_arg(
            row.get("arg_name", ""),
            row.get("drug_class", ""),
            row.get("resistance_mechanism", ""),
            row.get("amr_gene_family", ""),
        ),
        axis=1
    )

    grouped_records = []

    for mag_id, group in linked.groupby("mag_id", dropna=False):

        arg_names = unique_join(group["arg_name"])
        drug_classes = unique_join(group["drug_class"])
        mechanisms = unique_join(group["resistance_mechanism"])
        families = unique_join(group["amr_gene_family"])

        high_risk_group = group[group["high_risk_flag"] == True]
        high_risk_names = unique_join(high_risk_group["arg_name"]) if not high_risk_group.empty else "none"

        drug_class_set = set()
        for value in group["drug_class"]:
            if pd.isna(value):
                continue
            for part in str(value).replace(";", ",").split(","):
                part = part.strip()
                if part:
                    drug_class_set.add(part)

        grouped_records.append({
            "mag_id": mag_id,
            "arg_count": int(group["arg_gene_id"].nunique()),
            "arg_names": arg_names,
            "drug_classes": drug_classes,
            "resistance_mechanisms": mechanisms,
            "amr_gene_families": families,
            "high_risk_arg_count": int(high_risk_group["arg_gene_id"].nunique()),
            "high_risk_arg_names": high_risk_names,
            "drug_class_count": len(drug_class_set),
        })

    return pd.DataFrame(grouped_records)


# =============================================================================
# SUMMARIZE TABLE 2: BIOREMEDIATION POTENTIAL BY MAG
# =============================================================================

def summarize_dram_table(table2: pd.DataFrame):
    """
    Convert Table 2 into one row per MAG/bin with DRAM summary.
    """

    required = ["mag_id", "pathway_category", "pathway_name", "bioremediation_relevance"]

    missing = [col for col in required if col not in table2.columns]

    if missing:
        error(
            "Table 2 is missing required columns:\n"
            + "\n".join(f"  - {x}" for x in missing)
        )

    table2 = table2.copy()
    table2["mag_id"] = table2["mag_id"].apply(clean_mag_id)

    for col in [
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
        "detected_gene_count",
        "gene_or_module",
        "ko_id",
        "cazy_id",
        "pfam_id",
        "merops_id",
    ]:
        if col not in table2.columns:
            table2[col] = ""

    records = []

    for mag_id, group in table2.groupby("mag_id", dropna=False):

        high_group = group[group["bioremediation_relevance"].astype(str).str.lower() == "high"]
        medium_group = group[group["bioremediation_relevance"].astype(str).str.lower() == "medium"]

        # Gene count from detected_gene_count column.
        detected_counts = pd.to_numeric(group["detected_gene_count"], errors="coerce").fillna(0)

        high_counts = pd.to_numeric(high_group["detected_gene_count"], errors="coerce").fillna(0)
        medium_counts = pd.to_numeric(medium_group["detected_gene_count"], errors="coerce").fillna(0)

        records.append({
            "mag_id": mag_id,

            # Taxonomy and quality: take first non-empty.
            "gtdb_taxonomy": unique_join(group["gtdb_taxonomy"]),
            "domain": unique_join(group["domain"]),
            "phylum": unique_join(group["phylum"]),
            "class": unique_join(group["class"]),
            "order": unique_join(group["order"]),
            "family": unique_join(group["family"]),
            "genus": unique_join(group["genus"]),
            "species": unique_join(group["species"]),
            "completeness": unique_join(group["completeness"]),
            "contamination": unique_join(group["contamination"]),

            # DRAM summaries.
            "dram_feature_count": len(group),
            "total_detected_gene_count": int(detected_counts.sum()),
            "bioremediation_high_gene_count": int(high_counts.sum()),
            "bioremediation_medium_gene_count": int(medium_counts.sum()),
            "bioremediation_category_count": group["pathway_category"].nunique(),
            "bioremediation_categories": unique_join(group["pathway_category"]),
            "bioremediation_pathways": unique_join(group["pathway_name"]),
            "key_genes_or_modules": unique_join(group["gene_or_module"]),
            "ko_ids": unique_join(group["ko_id"]),
            "cazy_ids": unique_join(group["cazy_id"]),
            "pfam_ids": unique_join(group["pfam_id"]),
            "merops_ids": unique_join(group["merops_id"]),
        })

    return pd.DataFrame(records)


# =============================================================================
# EXCEL WRITER
# =============================================================================

def write_excel(output_xlsx, final_df, risky_useful, high_arg, bioremediation, low_priority, metadata):
    with pd.ExcelWriter(output_xlsx, engine="openpyxl") as writer:

        readme_df = pd.DataFrame(
            [{"field": key, "value": value} for key, value in metadata.items()]
        )

        readme_df.to_excel(writer, sheet_name="README", index=False)
        final_df.to_excel(writer, sheet_name="Table3_final_scoring", index=False)
        risky_useful.to_excel(writer, sheet_name="Risky_and_useful_MAGs", index=False)
        high_arg.to_excel(writer, sheet_name="High_ARG_risk_MAGs", index=False)
        bioremediation.to_excel(writer, sheet_name="Bioremediation_MAGs", index=False)
        low_priority.to_excel(writer, sheet_name="Low_priority_MAGs", index=False)

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

                ws.column_dimensions[col_letter].width = min(max(max_len + 2, 10), 65)


# =============================================================================
# MAIN
# =============================================================================

def main():

    parser = argparse.ArgumentParser(
        description="Create Table 3: MAG risk + bioremediation scoring."
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
        "--table1",
        default=None,
        help="Optional custom Table 1 path"
    )

    parser.add_argument(
        "--table2",
        default=None,
        help="Optional custom Table 2 path"
    )

    args = parser.parse_args()

    sample = args.sample
    project = Path(args.project)

    # =========================================================================
    # PATH DEFINITIONS
    # =========================================================================

    table1_path = (
        Path(args.table1)
        if args.table1
        else project / "results" / "final_tables" / sample / "01_ARG_gene_contig_bin_taxonomy_evidence.tsv"
    )

    table2_path = (
        Path(args.table2)
        if args.table2
        else project / "results" / "final_tables" / sample / "02_MAG_DRAM_pathway_metabolism.tsv"
    )

    final_dir = project / "results" / "final_tables" / sample
    final_dir.mkdir(parents=True, exist_ok=True)

    output_tsv = final_dir / "03_MAG_risk_bioremediation_scoring.tsv"
    output_xlsx = final_dir / "03_MAG_risk_bioremediation_scoring.xlsx"

    # =========================================================================
    # PRINT INPUT / OUTPUT SUMMARY
    # =========================================================================

    print("")
    print("======================================================")
    print("  Step 15: Table 3 MAG risk + bioremediation scoring")
    print("======================================================")
    print(f"  Sample ID               : {sample}")
    print(f"  Project folder          : {project}")
    print("")
    print("  INPUTS")
    print("  ----------------------------------------------------")
    print(f"  INPUT 1 Table 1 ARG     : {table1_path}")
    print(f"  INPUT 2 Table 2 DRAM    : {table2_path}")
    print("")
    print("  OUTPUTS")
    print("  ----------------------------------------------------")
    print(f"  OUTPUT 1 final TSV      : {output_tsv}")
    print(f"  OUTPUT 2 final Excel    : {output_xlsx}")
    print("======================================================")
    print("")

    # =========================================================================
    # READ TABLES
    # =========================================================================

    log("Reading Table 1: ARG evidence")
    table1 = read_table(table1_path, "Table 1 ARG evidence")

    log("Reading Table 2: DRAM pathway/metabolism")
    table2 = read_table(table2_path, "Table 2 DRAM pathway/metabolism")

    log(f"Table 1 rows loaded: {len(table1)}")
    log(f"Table 2 rows loaded: {len(table2)}")

    # =========================================================================
    # SUMMARIZE EACH TABLE BY MAG
    # =========================================================================

    log("Summarizing ARG burden by MAG")
    arg_summary = summarize_arg_table(table1)
    log(f"MAGs with linked ARGs: {len(arg_summary)}")

    log("Summarizing DRAM bioremediation potential by MAG")
    dram_summary = summarize_dram_table(table2)
    log(f"MAGs with DRAM features: {len(dram_summary)}")

    # =========================================================================
    # MERGE ARG SUMMARY WITH DRAM SUMMARY
    # =========================================================================

    log("Combining ARG risk and DRAM bioremediation summaries")

    all_mags = sorted(
        set(arg_summary["mag_id"].tolist() if "mag_id" in arg_summary.columns else [])
        |
        set(dram_summary["mag_id"].tolist() if "mag_id" in dram_summary.columns else [])
    )

    final_df = pd.DataFrame({"mag_id": all_mags})

    final_df = final_df.merge(dram_summary, how="left", on="mag_id")
    final_df = final_df.merge(arg_summary, how="left", on="mag_id")

    # Fill missing taxonomy/quality.
    for col in [
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
    ]:
        if col not in final_df.columns:
            final_df[col] = "missing"
        final_df[col] = final_df[col].fillna("missing")

    # Fill ARG columns.
    for col in [
        "arg_names",
        "drug_classes",
        "resistance_mechanisms",
        "amr_gene_families",
        "high_risk_arg_names",
    ]:
        if col not in final_df.columns:
            final_df[col] = "none"
        final_df[col] = final_df[col].fillna("none")

    for col in [
        "arg_count",
        "high_risk_arg_count",
        "drug_class_count",
    ]:
        if col not in final_df.columns:
            final_df[col] = 0
        final_df[col] = pd.to_numeric(final_df[col], errors="coerce").fillna(0).astype(int)

    # Fill DRAM/bioremediation columns.
    for col in [
        "bioremediation_categories",
        "bioremediation_pathways",
        "key_genes_or_modules",
        "ko_ids",
        "cazy_ids",
        "pfam_ids",
        "merops_ids",
    ]:
        if col not in final_df.columns:
            final_df[col] = "none"
        final_df[col] = final_df[col].fillna("none")

    for col in [
        "dram_feature_count",
        "total_detected_gene_count",
        "bioremediation_high_gene_count",
        "bioremediation_medium_gene_count",
        "bioremediation_category_count",
    ]:
        if col not in final_df.columns:
            final_df[col] = 0
        final_df[col] = pd.to_numeric(final_df[col], errors="coerce").fillna(0).astype(int)

    # =========================================================================
    # SCORE EACH MAG
    # =========================================================================

    log("Calculating risk and bioremediation scores")

    final_df["arg_risk_score"] = final_df.apply(
        lambda row: calculate_arg_risk_score(
            row["arg_count"],
            row["high_risk_arg_count"],
            row["drug_class_count"],
        ),
        axis=1
    )

    final_df["bioremediation_score"] = final_df.apply(
        lambda row: calculate_bioremediation_score(
            row["bioremediation_high_gene_count"],
            row["bioremediation_medium_gene_count"],
            row["bioremediation_category_count"],
        ),
        axis=1
    )

    final_df["combined_priority_score"] = (
        final_df["arg_risk_score"] + final_df["bioremediation_score"]
    )

    final_df["priority_group"] = final_df.apply(
        lambda row: assign_priority_group(
            row["arg_risk_score"],
            row["bioremediation_score"],
        ),
        axis=1
    )

    final_df["final_interpretation"] = final_df.apply(make_final_interpretation, axis=1)

    final_df["sample_id"] = sample

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

        "arg_count",
        "high_risk_arg_count",
        "drug_class_count",
        "arg_names",
        "high_risk_arg_names",
        "drug_classes",
        "resistance_mechanisms",
        "amr_gene_families",

        "dram_feature_count",
        "total_detected_gene_count",
        "bioremediation_high_gene_count",
        "bioremediation_medium_gene_count",
        "bioremediation_category_count",
        "bioremediation_categories",
        "bioremediation_pathways",
        "key_genes_or_modules",
        "ko_ids",
        "cazy_ids",
        "pfam_ids",
        "merops_ids",

        "arg_risk_score",
        "bioremediation_score",
        "combined_priority_score",
        "priority_group",
        "final_interpretation",
    ]

    existing_preferred = [col for col in preferred_cols if col in final_df.columns]
    remaining = [col for col in final_df.columns if col not in existing_preferred]

    final_df = final_df[existing_preferred + remaining]

    # Sort most important MAGs first.
    final_df = final_df.sort_values(
        by=["combined_priority_score", "arg_risk_score", "bioremediation_score", "mag_id"],
        ascending=[False, False, False, True]
    )

    # =========================================================================
    # SAVE TSV
    # =========================================================================

    final_df.to_csv(output_tsv, sep="\t", index=False)

    # =========================================================================
    # MAKE EXCEL SUBSHEETS
    # =========================================================================

    risky_useful = final_df[
        final_df["priority_group"] == "priority_watchlist_risky_and_bioremediation_relevant"
    ].copy()

    high_arg = final_df[
        final_df["arg_risk_score"] >= 3
    ].copy()

    bioremediation = final_df[
        final_df["bioremediation_score"] >= 3
    ].copy()

    low_priority = final_df[
        final_df["combined_priority_score"] <= 1
    ].copy()

    metadata = {
        "sample_id": sample,
        "input_Table1_ARG_taxonomy": str(table1_path),
        "input_Table2_DRAM_metabolism": str(table2_path),
        "output_TSV": str(output_tsv),
        "output_Excel": str(output_xlsx),
        "total_MAGs_scored": len(final_df),
        "MAGs_with_ARGs": int((final_df["arg_count"] > 0).sum()),
        "MAGs_with_high_ARG_risk_score_3_or_more": int((final_df["arg_risk_score"] >= 3).sum()),
        "MAGs_with_bioremediation_score_3_or_more": int((final_df["bioremediation_score"] >= 3).sum()),
        "MAGs_risky_and_bioremediation_relevant": len(risky_useful),
        "risk_score_range": "0 to 5",
        "bioremediation_score_range": "0 to 5",
        "combined_priority_score_range": "0 to 10",
        "note_1": "ARG risk score is based on ARG count, high-risk ARG categories, and drug-class diversity.",
        "note_2": "Bioremediation score is based on DRAM-derived high/medium relevance features and pathway-category diversity.",
        "note_3": "Scores are prioritization scores, not clinical or experimental validation.",
        "note_4": "The priority_watchlist group is the key group for risk-aware bioremediation mining.",
    }

    # =========================================================================
    # SAVE EXCEL
    # =========================================================================

    write_excel(
        output_xlsx=output_xlsx,
        final_df=final_df,
        risky_useful=risky_useful,
        high_arg=high_arg,
        bioremediation=bioremediation,
        low_priority=low_priority,
        metadata=metadata
    )

    # =========================================================================
    # FINAL SUMMARY
    # =========================================================================

    print("")
    print("======================================================")
    print(f"  Step 15 COMPLETE — {sample}")
    print("======================================================")
    print("")
    print("  INPUTS USED")
    print("  ----------------------------------------------------")
    print(f"  Table 1 ARG evidence       : {table1_path}")
    print(f"  Table 2 DRAM metabolism    : {table2_path}")
    print("")
    print("  OUTPUTS CREATED")
    print("  ----------------------------------------------------")
    print(f"  Final TSV table            : {output_tsv}")
    print(f"  Final Excel workbook       : {output_xlsx}")
    print("")
    print("  SUMMARY")
    print("  ----------------------------------------------------")
    print(f"  Total MAGs scored          : {len(final_df)}")
    print(f"  MAGs with ARGs             : {(final_df['arg_count'] > 0).sum()}")
    print(f"  High ARG risk MAGs         : {(final_df['arg_risk_score'] >= 3).sum()}")
    print(f"  Bioremediation MAGs        : {(final_df['bioremediation_score'] >= 3).sum()}")
    print(f"  Risky + useful MAGs        : {len(risky_useful)}")
    print("")
    print("  EXCEL SHEETS")
    print("  ----------------------------------------------------")
    print("  README")
    print("  Table3_final_scoring")
    print("  Risky_and_useful_MAGs")
    print("  High_ARG_risk_MAGs")
    print("  Bioremediation_MAGs")
    print("  Low_priority_MAGs")
    print("======================================================")


if __name__ == "__main__":
    main()