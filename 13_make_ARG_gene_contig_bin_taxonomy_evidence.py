#!/usr/bin/env python3
# =============================================================================
# Script : 13_make_ARG_gene_contig_bin_taxonomy_evidence.py
#
# Purpose:
#   Create final Table 1:
#
#       ARG gene → contig → good MAG/bin → GTDB taxonomy
#
#   This is the main ARG host-linking evidence table.
#
# =============================================================================
#
# INPUT 1 — RGI/CARD ARG table from Script 05
#
#   results/ARGs/<SAMPLE_ID>/<SAMPLE_ID>_rgi.txt
#
# INPUT 2 — CheckM2-good MAG FASTA folder from Script 09
#
#   results/MAGs/<SAMPLE_ID>/good_MAGs_75_10/
#
# INPUT 3 — GTDB-Tk taxonomy summary from Script 10
#
#   results/gtdbtk/<SAMPLE_ID>/<SAMPLE_ID>_GTDBTK_taxonomy_summary.tsv
#
# OUTPUTS
#
#   results/final_tables/<SAMPLE_ID>/01_ARG_gene_contig_bin_taxonomy_evidence.tsv
#   results/final_tables/<SAMPLE_ID>/01_ARG_gene_contig_bin_taxonomy_evidence.xlsx
#   results/final_tables/<SAMPLE_ID>/contig_to_goodMAG_map.tsv
#   results/final_tables/<SAMPLE_ID>/duplicated_contigs_in_goodMAGs.tsv
#
# USAGE
#
#   cd /mnt/e/kshiteeja/shotgun_project
#
#   python scripts/13_make_ARG_gene_contig_bin_taxonomy_evidence.py \
#       --sample ERR12510647
#
# =============================================================================

import argparse
import sys
from pathlib import Path
from collections import defaultdict

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


# =============================================================================
# GENERAL HELPERS
# =============================================================================

def normalize_colname(col: str) -> str:
    return str(col).strip().lower().replace(" ", "_").replace("-", "_")


def find_column(df: pd.DataFrame, candidates):
    normalized_map = {normalize_colname(c): c for c in df.columns}

    for candidate in candidates:
        candidate_norm = normalize_colname(candidate)
        if candidate_norm in normalized_map:
            return normalized_map[candidate_norm]

    return None


def clean_bin_id(value):
    """
    Normalize bin IDs for joining.

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

    for suffix in [".fa", ".fasta", ".fna"]:
        if value.endswith(suffix):
            value = value[: -len(suffix)]

    return value


def extract_arg_gene_id(orf_id):
    """
    Extract clean ARG gene ID from RGI ORF_ID.

    Example:
        k141_548087_1 # 90 # 1349 # -1 # ID=210_1

    Output:
        k141_548087_1
    """

    if pd.isna(orf_id):
        return ""

    return str(orf_id).split("#")[0].strip().split()[0]


# =============================================================================
# FASTA PARSING
# =============================================================================

def parse_fasta_headers(fasta_file: Path):
    """
    Extract contig IDs from one MAG FASTA file.
    """

    contigs = []

    with open(fasta_file, "r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if line.startswith(">"):
                header = line[1:].strip()
                contig_id = header.split()[0]
                contigs.append(contig_id)

    return contigs


def build_contig_to_mag_map(good_mag_dir: Path):
    """
    Build:
        contig_id → bin_id

    by reading all FASTA headers in:
        results/MAGs/<SAMPLE_ID>/good_MAGs_75_10/
    """

    fasta_files = []

    for pattern in ("*.fa", "*.fasta", "*.fna"):
        fasta_files.extend(good_mag_dir.glob(pattern))

    fasta_files = sorted(fasta_files)

    if not fasta_files:
        error(
            "No MAG FASTA files found in good MAG folder:\n"
            f"  {good_mag_dir}\n\n"
            "Expected files ending in .fa, .fasta, or .fna"
        )

    contig_to_mag = {}
    duplicated_contigs = defaultdict(list)

    for fasta in fasta_files:
        mag_id = clean_bin_id(fasta.name)
        contigs = parse_fasta_headers(fasta)

        for contig in contigs:
            if contig in contig_to_mag:
                duplicated_contigs[contig].append(mag_id)
            else:
                contig_to_mag[contig] = mag_id

    return contig_to_mag, duplicated_contigs, fasta_files


# =============================================================================
# GTDB TAXONOMY
# =============================================================================

def parse_gtdb_taxonomy(taxonomy):
    """
    Split GTDB taxonomy into ranks.
    """

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


def read_gtdb_taxonomy(gtdb_summary: Path):
    """
    Read GTDB-Tk summary and return standardized taxonomy table:

        bin_id
        gtdb_taxonomy
        domain
        phylum
        class
        order
        family
        genus
        species
    """

    if not gtdb_summary.exists():
        error(
            "GTDB-Tk taxonomy summary not found:\n"
            f"  {gtdb_summary}\n\n"
            "Run Script 10 before this script."
        )

    try:
        gtdb_df = pd.read_csv(gtdb_summary, sep="\t", dtype=str)
    except Exception as exc:
        error(
            "Could not read GTDB-Tk summary:\n"
            f"  {gtdb_summary}\n\n"
            f"Reason:\n  {exc}"
        )

    col_user_genome = find_column(gtdb_df, ["user_genome", "User Genome", "genome", "Genome"])
    col_classification = find_column(gtdb_df, ["classification", "Classification", "gtdb_taxonomy"])

    if col_user_genome is None:
        error(
            "GTDB summary is missing required column: user_genome\n\n"
            "Available columns:\n"
            + "\n".join(f"  - {x}" for x in gtdb_df.columns)
        )

    if col_classification is None:
        error(
            "GTDB summary is missing required column: classification\n\n"
            "Available columns:\n"
            + "\n".join(f"  - {x}" for x in gtdb_df.columns)
        )

    records = []

    for _, row in gtdb_df.iterrows():
        bin_id = clean_bin_id(row[col_user_genome])
        taxonomy = row[col_classification]
        ranks = parse_gtdb_taxonomy(taxonomy)

        records.append({
            "bin_id_clean": bin_id,
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
    out = out.drop_duplicates(subset=["bin_id_clean"])

    return out


# =============================================================================
# FILE READERS
# =============================================================================

def read_arg_table(arg_table: Path):
    """
    Read RGI/CARD ARG output table.
    """

    if not arg_table.exists():
        error(
            "ARG table not found:\n"
            f"  {arg_table}\n\n"
            "Expected default path:\n"
            "  results/ARGs/<SAMPLE_ID>/<SAMPLE_ID>_rgi.txt\n\n"
            "Check exact folder case: ARGs"
        )

    sep = "\t" if arg_table.suffix.lower() in [".txt", ".tsv"] else ","

    try:
        df = pd.read_csv(arg_table, sep=sep, dtype=str)
    except Exception as exc:
        error(
            "Failed to read ARG table:\n"
            f"  {arg_table}\n\n"
            f"Reason:\n  {exc}"
        )

    if df.empty:
        error(f"ARG table is empty: {arg_table}")

    return df


# =============================================================================
# EXCEL WRITER
# =============================================================================

def write_excel(output_xlsx, final_df, summary_mag, summary_taxonomy, unlinked_df, metadata):
    """
    Write final Excel workbook.
    """

    with pd.ExcelWriter(output_xlsx, engine="openpyxl") as writer:

        readme_df = pd.DataFrame(
            [{"field": key, "value": value} for key, value in metadata.items()]
        )

        readme_df.to_excel(writer, sheet_name="README", index=False)
        final_df.to_excel(writer, sheet_name="Table1_ARG_bin_taxonomy", index=False)
        summary_mag.to_excel(writer, sheet_name="Summary_by_MAG", index=False)
        summary_taxonomy.to_excel(writer, sheet_name="Summary_by_taxonomy", index=False)
        unlinked_df.to_excel(writer, sheet_name="Unlinked_ARGs", index=False)

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

                ws.column_dimensions[col_letter].width = min(max(max_len + 2, 10), 50)


# =============================================================================
# MAIN
# =============================================================================

def main():

    parser = argparse.ArgumentParser(
        description="Create Table 1: ARG gene → contig → bin → GTDB taxonomy evidence."
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
        "--arg-table",
        default=None,
        help="Optional custom ARG table path"
    )

    parser.add_argument(
        "--gtdb",
        default=None,
        help="Optional custom GTDB-Tk taxonomy summary path"
    )

    parser.add_argument(
        "--completeness",
        default="75",
        help="Completeness label used in good MAG folder name"
    )

    parser.add_argument(
        "--contamination",
        default="10",
        help="Contamination label used in good MAG folder name"
    )

    args = parser.parse_args()

    sample = args.sample
    project = Path(args.project)

    # =========================================================================
    # PATH DEFINITIONS
    # =========================================================================

    arg_table = (
        Path(args.arg_table)
        if args.arg_table
        else project / "results" / "ARGs" / sample / f"{sample}_rgi.txt"
    )

    good_mag_dir = (
        project
        / "results"
        / "MAGs"
        / sample
        / f"good_MAGs_{args.completeness}_{args.contamination}"
    )

    gtdb_summary = (
        Path(args.gtdb)
        if args.gtdb
        else project / "results" / "gtdbtk" / sample / f"{sample}_GTDBTK_taxonomy_summary.tsv"
    )

    final_dir = project / "results" / "final_tables" / sample
    final_dir.mkdir(parents=True, exist_ok=True)

    output_tsv = final_dir / "01_ARG_gene_contig_bin_taxonomy_evidence.tsv"
    output_xlsx = final_dir / "01_ARG_gene_contig_bin_taxonomy_evidence.xlsx"

    contig_map_tsv = final_dir / "contig_to_goodMAG_map.tsv"
    duplicated_contigs_tsv = final_dir / "duplicated_contigs_in_goodMAGs.tsv"

    # =========================================================================
    # PRINT INPUT / OUTPUT SUMMARY
    # =========================================================================

    print("")
    print("======================================================")
    print("  Step 13: Table 1 ARG → contig → bin → taxonomy")
    print("======================================================")
    print(f"  Sample ID                 : {sample}")
    print(f"  Project folder            : {project}")
    print("")
    print("  INPUTS")
    print("  ----------------------------------------------------")
    print(f"  INPUT 1 ARG table         : {arg_table}")
    print(f"  INPUT 2 good MAG folder   : {good_mag_dir}")
    print(f"  INPUT 3 GTDB taxonomy     : {gtdb_summary}")
    print("")
    print("  OUTPUTS")
    print("  ----------------------------------------------------")
    print(f"  OUTPUT 1 final TSV        : {output_tsv}")
    print(f"  OUTPUT 2 final Excel      : {output_xlsx}")
    print(f"  OUTPUT 3 contig-MAG map   : {contig_map_tsv}")
    print(f"  OUTPUT 4 duplicate report : {duplicated_contigs_tsv}")
    print("======================================================")
    print("")

    # =========================================================================
    # CHECK INPUTS
    # =========================================================================

    if not project.exists():
        error(f"Project folder not found: {project}")

    if not good_mag_dir.exists():
        error(
            "Good MAG folder not found:\n"
            f"  {good_mag_dir}\n\n"
            "Run Script 09 first."
        )

    # =========================================================================
    # READ ARG TABLE
    # =========================================================================

    arg_df = read_arg_table(arg_table)
    log(f"ARG rows loaded: {len(arg_df)}")

    col_orf = find_column(arg_df, ["ORF_ID", "ORF ID", "orf_id"])
    col_contig = find_column(arg_df, ["Contig", "contig"])
    col_start = find_column(arg_df, ["Start", "start"])
    col_stop = find_column(arg_df, ["Stop", "End", "stop", "end"])
    col_best_aro = find_column(arg_df, ["Best_Hit_ARO", "Best Hit ARO"])
    col_drug_class = find_column(arg_df, ["Drug Class", "Drug_Class"])
    col_mechanism = find_column(arg_df, ["Resistance Mechanism", "Resistance_Mechanism"])
    col_family = find_column(arg_df, ["AMR Gene Family", "AMR_Gene_Family"])

    col_orientation = find_column(arg_df, ["Orientation", "orientation"])
    col_cutoff = find_column(arg_df, ["Cut_Off", "Cut Off", "cut_off"])
    col_pass_bitscore = find_column(arg_df, ["Pass_Bitscore", "Pass Bitscore"])
    col_best_bitscore = find_column(arg_df, ["Best_Hit_Bitscore", "Best Hit Bitscore"])
    col_identity = find_column(arg_df, ["Best_Identities", "Best Identities"])
    col_aro = find_column(arg_df, ["ARO", "aro"])
    col_model_type = find_column(arg_df, ["Model_type", "Model type"])
    col_antibiotic = find_column(arg_df, ["Antibiotic", "antibiotic"])

    required_cols = {
        "ORF_ID": col_orf,
        "Contig": col_contig,
        "Start": col_start,
        "Stop": col_stop,
        "Best_Hit_ARO": col_best_aro,
        "Drug Class": col_drug_class,
        "Resistance Mechanism": col_mechanism,
        "AMR Gene Family": col_family,
    }

    missing = [name for name, col in required_cols.items() if col is None]

    if missing:
        error(
            "Required ARG columns missing:\n"
            + "\n".join(f"  - {x}" for x in missing)
            + "\n\nAvailable columns:\n"
            + "\n".join(f"  - {x}" for x in arg_df.columns)
        )

    log("Required ARG columns found")

    # =========================================================================
    # BUILD CONTIG → GOOD MAG MAP
    # =========================================================================

    log("Building contig → good MAG/bin map")

    contig_to_mag, duplicated_contigs, fasta_files = build_contig_to_mag_map(good_mag_dir)

    log(f"Good MAG FASTA files found: {len(fasta_files)}")
    log(f"Contigs mapped to good MAGs: {len(contig_to_mag)}")

    contig_map_df = pd.DataFrame(
        [{"contig_id": contig, "bin_id": mag} for contig, mag in contig_to_mag.items()]
    )

    if not contig_map_df.empty:
        contig_map_df = contig_map_df.sort_values(by=["bin_id", "contig_id"])

    contig_map_df.to_csv(contig_map_tsv, sep="\t", index=False)

    if duplicated_contigs:
        duplicated_df = pd.DataFrame(
            [
                {
                    "contig_id": contig,
                    "additional_mags": ";".join(mags),
                    "note": "Contig appeared in more than one good MAG FASTA"
                }
                for contig, mags in duplicated_contigs.items()
            ]
        )
        duplicated_df.to_csv(duplicated_contigs_tsv, sep="\t", index=False)
        warn(f"Duplicated contigs found: {len(duplicated_contigs)}")
    else:
        pd.DataFrame(
            columns=["contig_id", "additional_mags", "note"]
        ).to_csv(duplicated_contigs_tsv, sep="\t", index=False)

    # =========================================================================
    # READ GTDB TAXONOMY
    # =========================================================================

    log("Reading GTDB-Tk taxonomy summary")

    gtdb_taxonomy = read_gtdb_taxonomy(gtdb_summary)

    log(f"GTDB classified MAGs loaded: {len(gtdb_taxonomy)}")

    # =========================================================================
    # CREATE TABLE 1
    # =========================================================================

    log("Creating final Table 1")

    output = pd.DataFrame()

    output["sample_id"] = sample

    output["arg_gene_id"] = arg_df[col_orf].apply(extract_arg_gene_id)
    output["arg_orf_full_id"] = arg_df[col_orf].fillna("")

    output["arg_contig_id"] = arg_df[col_contig].fillna("").astype(str)
    output["arg_start"] = arg_df[col_start].fillna("")
    output["arg_end"] = arg_df[col_stop].fillna("")
    output["orientation"] = arg_df[col_orientation].fillna("") if col_orientation else ""

    output["arg_name"] = arg_df[col_best_aro].fillna("")
    output["aro_accession"] = arg_df[col_aro].fillna("") if col_aro else ""
    output["cut_off"] = arg_df[col_cutoff].fillna("") if col_cutoff else ""
    output["pass_bitscore"] = arg_df[col_pass_bitscore].fillna("") if col_pass_bitscore else ""
    output["best_hit_bitscore"] = arg_df[col_best_bitscore].fillna("") if col_best_bitscore else ""
    output["best_identity"] = arg_df[col_identity].fillna("") if col_identity else ""
    output["model_type"] = arg_df[col_model_type].fillna("") if col_model_type else ""

    output["drug_class"] = arg_df[col_drug_class].fillna("")
    output["resistance_mechanism"] = arg_df[col_mechanism].fillna("")
    output["amr_gene_family"] = arg_df[col_family].fillna("")
    output["antibiotic"] = arg_df[col_antibiotic].fillna("") if col_antibiotic else ""

    output["bin_id"] = output["arg_contig_id"].map(contig_to_mag).fillna("not_in_good_MAGs")
    output["bin_id_clean"] = output["bin_id"].apply(clean_bin_id)

    output["mag_quality_set"] = f"good_MAGs_{args.completeness}_{args.contamination}"

    output["binned_status"] = output.apply(
        lambda row: (
            "missing_contig_id"
            if str(row["arg_contig_id"]).strip() == ""
            else "binned_good_MAG"
            if row["bin_id"] != "not_in_good_MAGs"
            else "not_in_good_MAGs"
        ),
        axis=1
    )

    # Join GTDB taxonomy by bin ID.
    output = output.merge(
        gtdb_taxonomy,
        how="left",
        on="bin_id_clean"
    )

    # ARGs not in good MAGs should not have MAG taxonomy.
    not_in_good_mag = output["binned_status"] != "binned_good_MAG"

    for col in ["gtdb_taxonomy", "domain", "phylum", "class", "order", "family", "genus", "species"]:
        if col not in output.columns:
            output[col] = ""

    output.loc[not_in_good_mag, "gtdb_taxonomy"] = "not_applicable_not_in_good_MAG"
    output.loc[not_in_good_mag, "domain"] = "not_applicable"
    output.loc[not_in_good_mag, "phylum"] = "not_applicable"
    output.loc[not_in_good_mag, "class"] = "not_applicable"
    output.loc[not_in_good_mag, "order"] = "not_applicable"
    output.loc[not_in_good_mag, "family"] = "not_applicable"
    output.loc[not_in_good_mag, "genus"] = "not_applicable"
    output.loc[not_in_good_mag, "species"] = "not_applicable"

    # Linked to good MAG but absent from GTDB summary.
    missing_gtdb = (
        (output["binned_status"] == "binned_good_MAG")
        & (
            output["gtdb_taxonomy"].isna()
            | (output["gtdb_taxonomy"].astype(str).str.strip() == "")
        )
    )

    output.loc[missing_gtdb, "gtdb_taxonomy"] = "missing_in_GTDB_summary"
    output.loc[missing_gtdb, "domain"] = "missing"
    output.loc[missing_gtdb, "phylum"] = "missing"
    output.loc[missing_gtdb, "class"] = "missing"
    output.loc[missing_gtdb, "order"] = "missing"
    output.loc[missing_gtdb, "family"] = "missing"
    output.loc[missing_gtdb, "genus"] = "missing"
    output.loc[missing_gtdb, "species"] = "missing"

    # Remove helper column.
    output = output.drop(columns=["bin_id_clean"])

    # Sort table.
    sort_cols = [
        col for col in
        ["binned_status", "bin_id", "phylum", "genus", "species", "arg_name"]
        if col in output.columns
    ]

    output = output.sort_values(by=sort_cols)

    # Save TSV.
    output.to_csv(output_tsv, sep="\t", index=False)

    # =========================================================================
    # EXCEL SUMMARIES
    # =========================================================================

    linked = output[output["binned_status"] == "binned_good_MAG"].copy()
    unlinked = output[output["binned_status"] != "binned_good_MAG"].copy()

    if not linked.empty:
        summary_mag = (
            linked
            .groupby(["bin_id", "gtdb_taxonomy", "genus", "species"], dropna=False)
            .agg(
                arg_count=("arg_gene_id", "count"),
                arg_names=("arg_name", lambda x: "; ".join(sorted(set(map(str, x))))),
                drug_classes=("drug_class", lambda x: "; ".join(sorted(set(map(str, x))))),
                resistance_mechanisms=("resistance_mechanism", lambda x: "; ".join(sorted(set(map(str, x))))),
                amr_gene_families=("amr_gene_family", lambda x: "; ".join(sorted(set(map(str, x)))))
            )
            .reset_index()
        )

        summary_taxonomy = (
            linked
            .groupby(["domain", "phylum", "class", "order", "family", "genus", "species"], dropna=False)
            .agg(
                mag_count=("bin_id", lambda x: len(set(map(str, x)))),
                arg_count=("arg_gene_id", "count"),
                arg_names=("arg_name", lambda x: "; ".join(sorted(set(map(str, x))))),
                drug_classes=("drug_class", lambda x: "; ".join(sorted(set(map(str, x)))))
            )
            .reset_index()
        )
    else:
        summary_mag = pd.DataFrame()
        summary_taxonomy = pd.DataFrame()

    metadata = {
        "sample_id": sample,
        "input_ARG_table": str(arg_table),
        "input_good_MAG_FASTA_folder": str(good_mag_dir),
        "input_GTDB_taxonomy_summary": str(gtdb_summary),
        "output_TSV_table": str(output_tsv),
        "output_Excel_workbook": str(output_xlsx),
        "output_contig_to_MAG_map": str(contig_map_tsv),
        "output_duplicate_contig_report": str(duplicated_contigs_tsv),
        "mag_quality_set": f"good_MAGs_{args.completeness}_{args.contamination}",
        "total_ARG_rows": len(output),
        "ARGs_linked_to_good_MAGs": int((output["binned_status"] == "binned_good_MAG").sum()),
        "ARGs_not_in_good_MAGs": int((output["binned_status"] == "not_in_good_MAGs").sum()),
        "ARGs_missing_contig_id": int((output["binned_status"] == "missing_contig_id").sum()),
        "linked_ARGs_missing_GTDB_taxonomy": int(missing_gtdb.sum()),
        "interpretation_note_1": "This table links ARG calls to contigs, CheckM2-good MAGs, and GTDB-Tk taxonomy.",
        "interpretation_note_2": "ARGs marked not_in_good_MAGs are present in ARG output but their contigs were not found in the final good MAG folder.",
        "interpretation_note_3": "This is the final Table 1 evidence table for ARG host linkage.",
    }

    write_excel(
        output_xlsx=output_xlsx,
        final_df=output,
        summary_mag=summary_mag,
        summary_taxonomy=summary_taxonomy,
        unlinked_df=unlinked,
        metadata=metadata
    )

    # =========================================================================
    # FINAL SUMMARY
    # =========================================================================

    print("")
    print("======================================================")
    print(f"  Step 13 COMPLETE — {sample}")
    print("======================================================")
    print("")
    print("  INPUTS USED")
    print("  ----------------------------------------------------")
    print(f"  ARG table                  : {arg_table}")
    print(f"  Good MAG FASTA folder      : {good_mag_dir}")
    print(f"  GTDB-Tk taxonomy summary   : {gtdb_summary}")
    print("")
    print("  OUTPUTS CREATED")
    print("  ----------------------------------------------------")
    print(f"  Final TSV table            : {output_tsv}")
    print(f"  Final Excel workbook       : {output_xlsx}")
    print(f"  Contig → good MAG map      : {contig_map_tsv}")
    print(f"  Duplicate contig report    : {duplicated_contigs_tsv}")
    print("")
    print("  SUMMARY")
    print("  ----------------------------------------------------")
    print(f"  ARG rows processed         : {len(output)}")
    print(f"  Good MAG FASTA files       : {len(fasta_files)}")
    print(f"  Contigs mapped to MAGs     : {len(contig_to_mag)}")
    print(f"  GTDB classified MAGs       : {len(gtdb_taxonomy)}")
    print(f"  ARGs linked to good MAGs   : {(output['binned_status'] == 'binned_good_MAG').sum()}")
    print(f"  ARGs not in good MAGs      : {(output['binned_status'] == 'not_in_good_MAGs').sum()}")
    print(f"  Missing GTDB taxonomy      : {missing_gtdb.sum()}")
    print("")
    print("  MAIN OUTPUT")
    print("  ----------------------------------------------------")
    print(f"  {output_xlsx}")
    print("======================================================")


if __name__ == "__main__":
    main()