#!/usr/bin/env Rscript

# =============================================================================
# Script : 16_make_final_plots.R
#
# Purpose:
#   Create six final PNG figures from final shotgun metagenomics tables.
#
# Inputs:
#   results/final_tables/<SAMPLE_ID>/01_ARG_gene_contig_bin_taxonomy_evidence.tsv
#   results/final_tables/<SAMPLE_ID>/02_MAG_DRAM_pathway_metabolism.tsv
#   results/final_tables/<SAMPLE_ID>/03_MAG_risk_bioremediation_scoring.tsv
#
# Outputs:
#   results/plots/<SAMPLE_ID>/
#
# Figures:
#   01_priority_scatter.png
#   02_priority_group_barplot.png
#   03_top_ARG_MAGs_barplot.png
#   04_ARG_drug_class_heatmap.png
#   05_DRAM_pathway_heatmap.png
#   06_taxonomy_priority_barplot.png
#
# Usage:
#   cd /mnt/e/kshiteeja/shotgun_project
#   Rscript scripts/16_make_final_plots.R ERR12510647
# =============================================================================


# =============================================================================
# PACKAGE SETUP
# =============================================================================

required_packages <- c(
  "readr",
  "ggplot2",
  "dplyr",
  "tidyr",
  "stringr",
  "forcats",
  "scales"
)

install_missing_packages <- function(packages) {
  installed <- rownames(installed.packages())
  missing <- packages[!(packages %in% installed)]

  if (length(missing) > 0) {
    message("[INFO] Installing missing R packages: ", paste(missing, collapse = ", "))
    install.packages(missing, repos = "https://cloud.r-project.org")
  }
}

install_missing_packages(required_packages)

suppressPackageStartupMessages({
  library(readr)
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(forcats)
  library(scales)
})


# =============================================================================
# BASIC FUNCTIONS
# =============================================================================

log_msg <- function(x) {
  message("[INFO] ", x)
}

warn_msg <- function(x) {
  warning("[WARN] ", x, call. = FALSE)
}

stop_msg <- function(x) {
  stop("[ERROR] ", x, call. = FALSE)
}

safe_read_tsv <- function(path, label) {
  if (!file.exists(path)) {
    stop_msg(paste0(label, " not found:\n  ", path))
  }

  df <- readr::read_tsv(
    path,
    show_col_types = FALSE,
    col_types = readr::cols(.default = readr::col_character())
  )

  if (nrow(df) == 0) {
    warn_msg(paste0(label, " is empty: ", path))
  }

  return(df)
}

make_clean_label <- function(x) {
  x <- as.character(x)
  x <- stringr::str_replace_all(x, "_", " ")
  x <- stringr::str_replace_all(x, ";", "; ")
  x <- stringr::str_squish(x)
  return(x)
}

save_plot_png <- function(plot_object, output_prefix, width = 9, height = 6) {
  png_file <- paste0(output_prefix, ".png")

  ggplot2::ggsave(
    filename = png_file,
    plot = plot_object,
    width = width,
    height = height,
    dpi = 300
  )

  log_msg(paste0("Saved: ", png_file))
}

require_columns <- function(df, cols, table_name) {
  missing <- setdiff(cols, colnames(df))

  if (length(missing) > 0) {
    stop_msg(
      paste0(
        table_name,
        " is missing required columns:\n  ",
        paste(missing, collapse = "\n  ")
      )
    )
  }
}


# =============================================================================
# ARGUMENTS AND PATHS
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 1) {
  stop_msg("Please provide sample ID. Example: Rscript scripts/16_make_final_plots.R ERR12510647")
}

sample_id <- args[1]

project_dir <- "/mnt/e/kshiteeja/shotgun_project"

table_dir <- file.path(project_dir, "results", "final_tables", sample_id)
plot_dir <- file.path(project_dir, "results", "plots", sample_id)

dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)

table1_path <- file.path(table_dir, "01_ARG_gene_contig_bin_taxonomy_evidence.tsv")
table2_path <- file.path(table_dir, "02_MAG_DRAM_pathway_metabolism.tsv")
table3_path <- file.path(table_dir, "03_MAG_risk_bioremediation_scoring.tsv")

log_msg(paste0("Sample ID: ", sample_id))
log_msg(paste0("Table folder: ", table_dir))
log_msg(paste0("Plot folder: ", plot_dir))


# =============================================================================
# READ TABLES
# =============================================================================

table1 <- safe_read_tsv(table1_path, "Table 1 ARG evidence")
table2 <- safe_read_tsv(table2_path, "Table 2 DRAM metabolism")
table3 <- safe_read_tsv(table3_path, "Table 3 final scoring")

log_msg(paste0("Table 1 rows: ", nrow(table1)))
log_msg(paste0("Table 2 rows: ", nrow(table2)))
log_msg(paste0("Table 3 rows: ", nrow(table3)))


# =============================================================================
# STANDARDIZE TABLE 3
# =============================================================================

numeric_cols_table3 <- c(
  "arg_count",
  "high_risk_arg_count",
  "drug_class_count",
  "dram_feature_count",
  "total_detected_gene_count",
  "bioremediation_high_gene_count",
  "bioremediation_medium_gene_count",
  "bioremediation_category_count",
  "arg_risk_score",
  "bioremediation_score",
  "combined_priority_score"
)

for (col in numeric_cols_table3) {
  if (col %in% colnames(table3)) {
    table3[[col]] <- suppressWarnings(as.numeric(table3[[col]]))
    table3[[col]][is.na(table3[[col]])] <- 0
  }
}

if (!"priority_group" %in% colnames(table3)) {
  table3$priority_group <- "missing"
}

if (!"genus" %in% colnames(table3)) {
  table3$genus <- "missing"
}

if (!"species" %in% colnames(table3)) {
  table3$species <- "missing"
}

if (!"mag_id" %in% colnames(table3)) {
  stop_msg("Table 3 must contain mag_id column.")
}

table3 <- table3 %>%
  mutate(
    priority_group_clean = make_clean_label(priority_group),
    genus_clean = if_else(is.na(genus) | genus == "" | genus == "none", "unresolved", genus),
    species_clean = if_else(is.na(species) | species == "" | species == "none", "unresolved", species),
    organism_label = str_squish(paste(genus_clean, species_clean)),
    organism_label = if_else(
      organism_label %in% c("missing missing", "none none", "unresolved unresolved"),
      "unresolved taxonomy",
      organism_label
    )
  )


# =============================================================================
# FIGURE 1: ARG RISK SCORE VS BIOREMEDIATION SCORE
# =============================================================================

require_columns(
  table3,
  c("mag_id", "arg_risk_score", "bioremediation_score", "combined_priority_score", "priority_group"),
  "Table 3"
)

fig1 <- ggplot(
  table3,
  aes(
    x = arg_risk_score,
    y = bioremediation_score,
    size = combined_priority_score,
    shape = priority_group_clean
  )
) +
  geom_point(alpha = 0.85) +
  geom_jitter(width = 0.08, height = 0.08, alpha = 0.4) +
  scale_x_continuous(breaks = 0:5, limits = c(-0.2, 5.2)) +
  scale_y_continuous(breaks = 0:5, limits = c(-0.2, 5.2)) +
  scale_size_continuous(range = c(2.5, 8)) +
  labs(
    title = paste0("MAG ARG risk vs bioremediation potential: ", sample_id),
    x = "ARG risk score",
    y = "Bioremediation score",
    size = "Combined priority score",
    shape = "Priority group"
  ) +
  theme_bw(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold"),
    legend.position = "right"
  )

save_plot_png(
  fig1,
  file.path(plot_dir, "01_priority_scatter"),
  width = 10,
  height = 7
)


# =============================================================================
# FIGURE 2: NUMBER OF MAGS PER PRIORITY GROUP
# =============================================================================

priority_counts <- table3 %>%
  count(priority_group_clean, name = "mag_count") %>%
  arrange(desc(mag_count)) %>%
  mutate(priority_group_clean = fct_reorder(priority_group_clean, mag_count))

fig2 <- ggplot(
  priority_counts,
  aes(x = priority_group_clean, y = mag_count)
) +
  geom_col(width = 0.75) +
  coord_flip() +
  labs(
    title = paste0("MAGs per priority group: ", sample_id),
    x = "Priority group",
    y = "Number of MAGs"
  ) +
  theme_bw(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold")
  )

save_plot_png(
  fig2,
  file.path(plot_dir, "02_priority_group_barplot"),
  width = 9,
  height = 6
)


# =============================================================================
# FIGURE 3: TOP ARG-CARRYING MAGS
# =============================================================================

top_arg_mags <- table3 %>%
  filter(arg_count > 0) %>%
  arrange(desc(arg_count), desc(arg_risk_score)) %>%
  slice_head(n = 20) %>%
  mutate(
    mag_label = paste0(mag_id, " | ", organism_label),
    mag_label = fct_reorder(mag_label, arg_count)
  )

if (nrow(top_arg_mags) == 0) {

  warn_msg("No MAGs with ARGs found in Table 3. Creating empty placeholder Figure 3.")

  fig3 <- ggplot() +
    annotate(
      "text",
      x = 1,
      y = 1,
      label = "No ARG-linked MAGs found",
      size = 5
    ) +
    theme_void() +
    labs(title = paste0("Top ARG-carrying MAGs: ", sample_id))

} else {

  fig3 <- ggplot(
    top_arg_mags,
    aes(x = mag_label, y = arg_count)
  ) +
    geom_col(width = 0.75) +
    coord_flip() +
    labs(
      title = paste0("Top ARG-carrying MAGs: ", sample_id),
      x = "MAG | organism",
      y = "ARG count"
    ) +
    theme_bw(base_size = 11) +
    theme(
      plot.title = element_text(face = "bold")
    )
}

save_plot_png(
  fig3,
  file.path(plot_dir, "03_top_ARG_MAGs_barplot"),
  width = 11,
  height = 7
)


# =============================================================================
# FIGURE 4: ARG DRUG-CLASS HEATMAP BY MAG
# =============================================================================

require_columns(
  table1,
  c("bin_id", "binned_status", "drug_class", "arg_gene_id"),
  "Table 1"
)

arg_heatmap_df <- table1 %>%
  filter(binned_status == "binned_good_MAG") %>%
  mutate(
    mag_id = bin_id,
    drug_class = if_else(is.na(drug_class) | drug_class == "", "unknown", drug_class)
  ) %>%
  separate_rows(drug_class, sep = ";|,") %>%
  mutate(
    drug_class = str_squish(drug_class),
    drug_class = if_else(drug_class == "", "unknown", drug_class)
  ) %>%
  count(mag_id, drug_class, name = "arg_count") %>%
  group_by(mag_id) %>%
  mutate(total_arg_count = sum(arg_count)) %>%
  ungroup() %>%
  filter(total_arg_count > 0)

if (nrow(arg_heatmap_df) == 0) {

  warn_msg("No binned ARG drug-class data found. Creating empty placeholder Figure 4.")

  fig4 <- ggplot() +
    annotate(
      "text",
      x = 1,
      y = 1,
      label = "No binned ARG drug-class data found",
      size = 5
    ) +
    theme_void() +
    labs(title = paste0("ARG drug-class heatmap: ", sample_id))

} else {

  top_heatmap_mags <- arg_heatmap_df %>%
    distinct(mag_id, total_arg_count) %>%
    arrange(desc(total_arg_count)) %>%
    slice_head(n = 30) %>%
    pull(mag_id)

  arg_heatmap_plot_df <- arg_heatmap_df %>%
    filter(mag_id %in% top_heatmap_mags) %>%
    mutate(
      mag_id = fct_reorder(mag_id, total_arg_count),
      drug_class = fct_infreq(drug_class)
    )

  fig4 <- ggplot(
    arg_heatmap_plot_df,
    aes(x = drug_class, y = mag_id, fill = arg_count)
  ) +
    geom_tile(color = "white", linewidth = 0.2) +
    scale_fill_gradient(low = "white", high = "black") +
    labs(
      title = paste0("ARG drug classes across MAGs: ", sample_id),
      x = "Drug class",
      y = "MAG",
      fill = "ARG count"
    ) +
    theme_bw(base_size = 11) +
    theme(
      plot.title = element_text(face = "bold"),
      axis.text.x = element_text(angle = 45, hjust = 1),
      panel.grid = element_blank()
    )
}

save_plot_png(
  fig4,
  file.path(plot_dir, "04_ARG_drug_class_heatmap"),
  width = 11,
  height = 8
)


# =============================================================================
# FIGURE 5: DRAM PATHWAY-CATEGORY HEATMAP BY MAG
# =============================================================================

require_columns(
  table2,
  c("mag_id", "pathway_category", "detected_gene_count"),
  "Table 2"
)

dram_heatmap_df <- table2 %>%
  mutate(
    pathway_category = if_else(
      is.na(pathway_category) | pathway_category == "",
      "unknown",
      pathway_category
    ),
    detected_gene_count = suppressWarnings(as.numeric(detected_gene_count)),
    detected_gene_count = if_else(is.na(detected_gene_count), 0, detected_gene_count)
  ) %>%
  group_by(mag_id, pathway_category) %>%
  summarise(
    detected_gene_count = sum(detected_gene_count, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  group_by(mag_id) %>%
  mutate(total_detected = sum(detected_gene_count, na.rm = TRUE)) %>%
  ungroup() %>%
  filter(total_detected > 0)

if (nrow(dram_heatmap_df) == 0) {

  warn_msg("No DRAM pathway-category data found. Creating empty placeholder Figure 5.")

  fig5 <- ggplot() +
    annotate(
      "text",
      x = 1,
      y = 1,
      label = "No DRAM pathway-category data found",
      size = 5
    ) +
    theme_void() +
    labs(title = paste0("DRAM pathway heatmap: ", sample_id))

} else {

  top_dram_mags <- dram_heatmap_df %>%
    distinct(mag_id, total_detected) %>%
    arrange(desc(total_detected)) %>%
    slice_head(n = 30) %>%
    pull(mag_id)

  dram_heatmap_plot_df <- dram_heatmap_df %>%
    filter(mag_id %in% top_dram_mags) %>%
    mutate(
      pathway_category_clean = make_clean_label(pathway_category),
      mag_id = fct_reorder(mag_id, total_detected),
      pathway_category_clean = fct_infreq(pathway_category_clean)
    )

  fig5 <- ggplot(
    dram_heatmap_plot_df,
    aes(x = pathway_category_clean, y = mag_id, fill = detected_gene_count)
  ) +
    geom_tile(color = "white", linewidth = 0.2) +
    scale_fill_gradient(low = "white", high = "black") +
    labs(
      title = paste0("DRAM pathway categories across MAGs: ", sample_id),
      x = "Pathway category",
      y = "MAG",
      fill = "Detected gene count"
    ) +
    theme_bw(base_size = 11) +
    theme(
      plot.title = element_text(face = "bold"),
      axis.text.x = element_text(angle = 45, hjust = 1),
      panel.grid = element_blank()
    )
}

save_plot_png(
  fig5,
  file.path(plot_dir, "05_DRAM_pathway_heatmap"),
  width = 12,
  height = 8
)


# =============================================================================
# FIGURE 6: TAXONOMY PRIORITY BARPLOT
# =============================================================================

taxonomy_summary <- table3 %>%
  mutate(
    genus_clean = if_else(
      is.na(genus) | genus == "" | genus == "none" | genus == "missing",
      "unresolved",
      genus
    )
  ) %>%
  count(genus_clean, priority_group_clean, name = "mag_count") %>%
  group_by(genus_clean) %>%
  mutate(total_mags = sum(mag_count)) %>%
  ungroup() %>%
  arrange(desc(total_mags)) %>%
  mutate(
    genus_clean = fct_reorder(genus_clean, total_mags)
  )

top_genera <- taxonomy_summary %>%
  distinct(genus_clean, total_mags) %>%
  arrange(desc(total_mags)) %>%
  slice_head(n = 20) %>%
  pull(genus_clean)

taxonomy_plot_df <- taxonomy_summary %>%
  filter(genus_clean %in% top_genera)

if (nrow(taxonomy_plot_df) == 0) {

  warn_msg("No taxonomy data found. Creating empty placeholder Figure 6.")

  fig6 <- ggplot() +
    annotate(
      "text",
      x = 1,
      y = 1,
      label = "No taxonomy data found",
      size = 5
    ) +
    theme_void() +
    labs(title = paste0("Taxonomy and priority groups: ", sample_id))

} else {

  fig6 <- ggplot(
    taxonomy_plot_df,
    aes(x = genus_clean, y = mag_count, fill = priority_group_clean)
  ) +
    geom_col(width = 0.75) +
    coord_flip() +
    labs(
      title = paste0("Priority groups across top genera: ", sample_id),
      x = "Genus",
      y = "Number of MAGs",
      fill = "Priority group"
    ) +
    theme_bw(base_size = 11) +
    theme(
      plot.title = element_text(face = "bold")
    )
}

save_plot_png(
  fig6,
  file.path(plot_dir, "06_taxonomy_priority_barplot"),
  width = 11,
  height = 7
)


# =============================================================================
# SESSION INFO FOR REPRODUCIBILITY
# =============================================================================

session_file <- file.path(plot_dir, "R_session_info.txt")

sink(session_file)
cat("Script: 16_make_final_plots.R\n")
cat("Sample ID:", sample_id, "\n")
cat("Project directory:", project_dir, "\n")
cat("Plot directory:", plot_dir, "\n")
cat("Date:", as.character(Sys.time()), "\n\n")
sessionInfo()
sink()

log_msg(paste0("Saved R session info: ", session_file))
log_msg("All PNG plots completed successfully.")