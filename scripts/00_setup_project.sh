#!/bin/bash

###############################################################################
# 00_setup_project.sh
#
# Purpose:
#   Project-level setup confirmation script for the shotgun metagenomics pipeline.
#
# This script checks:
#   1. Project folder structure
#   2. Conda availability
#   3. Required conda environments
#   4. Tools inside each environment
#   5. Tool versions where possible
#   6. Python/R package dependencies for table scripts
#   7. Database folders and key database files
#   8. DRAM, GTDB-Tk, CheckM2, CARD database paths
#   9. Script files and executable permissions
#   10. Disk space, RAM, CPU, write permissions
#
# Important:
#   This script is NOT sample-specific.
#   Run it once after setup, and whenever you update tools/databases/scripts.
#
# Usage:
#   bash scripts/00_setup_project.sh
#
###############################################################################

set -u

###############################################################################
# USER CONFIGURATION
###############################################################################

PROJECT="/mnt/e/kshiteeja/shotgun_project"

# Databases are stored directly on E drive, NOT inside the project folder.
DB_ROOT="/mnt/e/Databases"

GTDBTK_DB="$DB_ROOT/GTDBTK/release232"
CHECKM2_DB="$DB_ROOT/checkm2_database"
DRAM_DB="$DB_ROOT/DRAM"
CARD_DB="$DB_ROOT/CARD"

MIN_FREE_GB=50

###############################################################################
# COLORS
###############################################################################

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
NC="\033[0m"

###############################################################################
# COUNTERS
###############################################################################

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

###############################################################################
# FUNCTIONS
###############################################################################

pass_msg() {
    echo -e "${GREEN}[OK]${NC} $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

warn_msg() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    WARN_COUNT=$((WARN_COUNT + 1))
}

fail_msg() {
    echo -e "${RED}[MISSING/FAIL]${NC} $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

section() {
    echo
    echo -e "${BLUE}====================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}====================================================================${NC}"
}

check_dir() {
    local path="$1"
    local label="$2"

    if [ -d "$path" ]; then
        pass_msg "$label exists: $path"
    else
        fail_msg "$label missing: $path"
    fi
}

check_optional_dir() {
    local path="$1"
    local label="$2"

    if [ -d "$path" ]; then
        pass_msg "$label exists: $path"
    else
        warn_msg "$label not found yet: $path"
    fi
}

check_file() {
    local path="$1"
    local label="$2"

    if [ -s "$path" ]; then
        pass_msg "$label exists and is not empty: $path"
    elif [ -f "$path" ]; then
        warn_msg "$label exists but is empty: $path"
    else
        fail_msg "$label missing: $path"
    fi
}

check_optional_file() {
    local path="$1"
    local label="$2"

    if [ -s "$path" ]; then
        pass_msg "$label exists and is not empty: $path"
    elif [ -f "$path" ]; then
        warn_msg "$label exists but is empty: $path"
    else
        warn_msg "$label not found yet: $path"
    fi
}

check_env_exists() {
    local env="$1"

    if command -v conda >/dev/null 2>&1; then
        if conda env list | awk '{print $1}' | grep -qx "$env"; then
            pass_msg "Conda environment exists: $env"
        else
            fail_msg "Conda environment missing: $env"
        fi
    else
        fail_msg "Cannot check environment because conda is not available: $env"
    fi
}

check_tool_in_env() {
    local env="$1"
    local tool="$2"

    if command -v conda >/dev/null 2>&1; then
        if conda run -n "$env" bash -c "command -v $tool >/dev/null 2>&1" >/dev/null 2>&1; then
            pass_msg "$tool found in environment: $env"
        else
            fail_msg "$tool missing in environment: $env"
        fi
    else
        fail_msg "Cannot check $tool because conda is not available"
    fi
}

check_tool_any_in_env() {
    local env="$1"
    local label="$2"
    shift 2
    local tools=("$@")
    local found="NO"

    if ! command -v conda >/dev/null 2>&1; then
        fail_msg "Cannot check $label because conda is not available"
        return
    fi

    for tool in "${tools[@]}"; do
        if conda run -n "$env" bash -c "command -v $tool >/dev/null 2>&1" >/dev/null 2>&1; then
            pass_msg "$label found in $env as command: $tool"
            found="YES"
            break
        fi
    done

    if [ "$found" = "NO" ]; then
        fail_msg "$label missing in environment $env. Tried: ${tools[*]}"
    fi
}

check_tool_version_in_env() {
    local env="$1"
    local tool="$2"
    local version_cmd="$3"

    if command -v conda >/dev/null 2>&1; then
        if conda run -n "$env" bash -c "command -v $tool >/dev/null 2>&1" >/dev/null 2>&1; then
            version_output=$(conda run -n "$env" bash -c "$version_cmd" 2>&1 | head -n 2 | tr '\n' ' ')
            pass_msg "$tool found in $env | Version/info: $version_output"
        else
            fail_msg "$tool missing in environment: $env"
        fi
    else
        fail_msg "Cannot check $tool because conda is not available"
    fi
}

check_python_package_in_env() {
    local env="$1"
    local package="$2"

    if command -v conda >/dev/null 2>&1; then
        if conda run -n "$env" python -c "import $package; print(getattr($package, '__version__', 'installed'))" >/dev/null 2>&1; then
            version_output=$(conda run -n "$env" python -c "import $package; print(getattr($package, '__version__', 'installed'))" 2>/dev/null)
            pass_msg "Python package $package found in $env | $version_output"
        else
            fail_msg "Python package $package missing in environment: $env"
        fi
    else
        fail_msg "Cannot check Python package $package because conda is not available"
    fi
}

check_r_package_in_env() {
    local env="$1"
    local package="$2"

    if command -v conda >/dev/null 2>&1; then
        if conda run -n "$env" Rscript -e "library($package); cat(as.character(packageVersion('$package')))" >/dev/null 2>&1; then
            version_output=$(conda run -n "$env" Rscript -e "library($package); cat(as.character(packageVersion('$package')))" 2>/dev/null)
            pass_msg "R package $package found in $env | $version_output"
        else
            warn_msg "R package $package missing or not loadable in environment: $env"
        fi
    else
        warn_msg "Cannot check R package $package because conda is not available"
    fi
}

###############################################################################
# HEADER
###############################################################################

clear

echo "===================================================================="
echo "SHOTGUN METAGENOMICS PROJECT SETUP CONFIRMATION"
echo "===================================================================="
echo "Project path : $PROJECT"
echo "Database root: $DB_ROOT"
echo "Date         : $(date)"
echo "User         : $(whoami)"
echo "Hostname     : $(hostname)"
echo "===================================================================="

###############################################################################
# 1. SYSTEM CHECK
###############################################################################

section "1. SYSTEM CHECK"

echo "Current directory:"
pwd

echo
echo "Kernel / OS:"
uname -a

echo
echo "Disk space near project path:"
df -h "$PROJECT" 2>/dev/null || df -h

echo
echo "Memory:"
free -h || warn_msg "free command not available"

echo
echo "CPU cores:"
nproc || warn_msg "nproc command not available"

echo
echo "Free space check:"
if [ -d "$PROJECT" ]; then
    FREE_GB=$(df -BG "$PROJECT" | awk 'NR==2 {gsub("G","",$4); print $4}')
    if [ "$FREE_GB" -ge "$MIN_FREE_GB" ]; then
        pass_msg "Free disk space is acceptable: ${FREE_GB}G available"
    else
        warn_msg "Low disk space: ${FREE_GB}G available. Recommended at least ${MIN_FREE_GB}G"
    fi
else
    warn_msg "Project folder does not exist yet, cannot calculate project-specific free space"
fi

###############################################################################
# 2. CREATE AND CHECK BASE PROJECT FOLDERS
###############################################################################

section "2. CREATE AND CHECK BASE PROJECT FOLDERS"

if [ ! -d "$PROJECT" ]; then
    mkdir -p "$PROJECT"
    pass_msg "Created project folder: $PROJECT"
else
    pass_msg "Project folder already exists: $PROJECT"
fi

MAIN_DIRS=(
    "data"
    "data/raw"
    "data/clean"
    "results"
    "results/qc"
    "results/assembly"
    "results/gene_prediction"
    "results/CDHIT"
    "results/ARGs"
    "results/binning"
    "results/bin_refinement"
    "results/checkm2"
    "results/gtdbtk"
    "results/DRAM"
    "results/final_tables"
    "scripts"
    "logs"
    
)

echo
echo "Creating required base folders if missing..."

for d in "${MAIN_DIRS[@]}"; do
    mkdir -p "$PROJECT/$d"
done

pass_msg "Required base project folders created or already present"

echo
echo "Checking base project folders..."

for d in "${MAIN_DIRS[@]}"; do
    check_dir "$PROJECT/$d" "$d"
done

###############################################################################
# 3. PIPELINE SCRIPT FILE CHECK
###############################################################################

section "3. PIPELINE SCRIPT FILE CHECK"

EXPECTED_SCRIPTS=(
    "00_setup_project.sh"
    "01_read_qc.sh"
    "02_assembly.sh"
    "03_gene_prediction.sh"
    "04_cdhit.sh"
    "05_rgi_arg_detection.sh"
    "06_prepare_metawrap_reads.sh"
    "07_metawrap_binning.sh"
    "08_bin_refinement.sh"
    "09_checkm2.sh"
    "10_gtdbtk.sh"
    "11_dram_annotation.sh"
    "12_arg_contig_bin_table.sh"
    "13_mag_arg_taxonomy_table.sh"
    "14_dram_pathway_table.sh"
    "15_final_integrated_table.sh"
    "master_script.sh"
)

for script in "${EXPECTED_SCRIPTS[@]}"; do
    if [ -f "$PROJECT/scripts/$script" ]; then
        pass_msg "Script found: scripts/$script"

        if [ -x "$PROJECT/scripts/$script" ]; then
            pass_msg "Script is executable: scripts/$script"
        else
            warn_msg "Script is not executable. Fix with: chmod +x $PROJECT/scripts/$script"
        fi
    else
        warn_msg "Script not found yet: scripts/$script"
    fi
done

###############################################################################
# 4. CONDA CHECK
###############################################################################

section "4. CONDA CHECK"

if command -v conda >/dev/null 2>&1; then
    pass_msg "Conda is available"
    conda --version
else
    fail_msg "Conda is not available in this shell"
    echo
    echo "Possible fix:"
    echo "  source ~/miniconda3/etc/profile.d/conda.sh"
fi

echo
echo "Available conda environments:"
conda env list 2>/dev/null || warn_msg "Could not list conda environments"

###############################################################################
# 5. REQUIRED CONDA ENVIRONMENT CHECK
###############################################################################

section "5. REQUIRED CONDA ENVIRONMENT CHECK"

REQUIRED_ENVS=(
    "shotgun_qc"
    "shotgun_assembly"
    "shotgun_gene"
    "shotgun_arg"
    "metawrap-env"
    "checkm2_env"
    "shotgun_gtdbtk"
    "dram_env"
    "shotgun_tables"
)

for env in "${REQUIRED_ENVS[@]}"; do
    check_env_exists "$env"
done

###############################################################################
# 6. TOOL CHECK INSIDE ENVIRONMENTS
###############################################################################

section "6. TOOL CHECK INSIDE CONDA ENVIRONMENTS"

echo
echo "QC tools:"
check_tool_version_in_env "shotgun_qc" "fastp" "fastp --version"
check_tool_version_in_env "shotgun_qc" "fastqc" "fastqc --version"
check_tool_version_in_env "shotgun_qc" "multiqc" "multiqc --version"

echo
echo "Assembly tools:"
check_tool_version_in_env "shotgun_assembly" "megahit" "megahit --version"

echo
echo "Gene prediction tools:"
check_tool_version_in_env "shotgun_gene" "prodigal" "prodigal -v"

echo
echo "Clustering tools:"
check_tool_any_in_env "shotgun_gene" "CD-HIT" "cd-hit" "cd-hit-est"

echo
echo "ARG detection tools:"
check_tool_version_in_env "shotgun_arg" "rgi" "rgi --version"

echo
echo "MetaWRAP and binning tools:"
check_tool_in_env "metawrap-env" "metawrap"
check_tool_any_in_env "metawrap-env" "MetaBAT2" "metabat2" "jgi_summarize_bam_contig_depths"
check_tool_any_in_env "metawrap-env" "MaxBin2" "run_MaxBin.pl"
check_tool_any_in_env "metawrap-env" "CONCOCT" "concoct"

echo
echo "Bin quality tools:"
check_tool_any_in_env "metawrap-env" "CheckM1 / MetaWRAP bin-refinement dependency" "checkm"
check_tool_any_in_env "checkm2_env" "CheckM2" "checkm2" "CheckM2"

echo
echo "Taxonomy tools:"
check_tool_version_in_env "shotgun_gtdbtk" "gtdbtk" "gtdbtk --version"

echo
echo "Functional annotation tools:"
check_tool_in_env "dram_env" "DRAM.py"
check_tool_in_env "dram_env" "DRAM-setup.py"

echo
echo "Table-generation tools:"
check_tool_version_in_env "shotgun_tables" "python" "python --version"
check_tool_any_in_env "shotgun_tables" "Python3" "python3"

###############################################################################
# 7. PYTHON AND R PACKAGE DEPENDENCY CHECK
###############################################################################

section "7. PYTHON AND R PACKAGE DEPENDENCY CHECK"

echo
echo "Python packages for final table generation:"
check_python_package_in_env "shotgun_tables" "pandas"
check_python_package_in_env "shotgun_tables" "numpy"
check_python_package_in_env "shotgun_tables" "openpyxl"

echo
echo "Optional Python packages:"
check_python_package_in_env "shotgun_tables" "matplotlib"

echo
echo "R packages for plotting/summary scripts, if used:"
check_r_package_in_env "shotgun_tables" "readr"
check_r_package_in_env "shotgun_tables" "dplyr"
check_r_package_in_env "shotgun_tables" "ggplot2"
check_r_package_in_env "shotgun_tables" "stringr"
check_r_package_in_env "shotgun_tables" "tidyr"

###############################################################################
# 8. DATABASE CHECK
###############################################################################

section "8. DATABASE CHECK"

check_dir "$DB_ROOT" "Database root"
check_dir "$GTDBTK_DB" "GTDB-Tk database"
check_dir "$CHECKM2_DB" "CheckM2 database"
check_dir "$DRAM_DB" "DRAM database folder"
check_optional_dir "$CARD_DB" "CARD database folder"

echo
echo "Database size overview:"
du -sh "$DB_ROOT"/* 2>/dev/null || warn_msg "Could not calculate database folder sizes"

###############################################################################
# 9. DATABASE-SPECIFIC FILE CHECKS
###############################################################################

section "9. DATABASE-SPECIFIC FILE CHECKS"

echo
echo "GTDB-Tk database basic check:"
if [ -d "$GTDBTK_DB" ]; then
    gtdb_count=$(find "$GTDBTK_DB" -type f 2>/dev/null | wc -l)
    if [ "$gtdb_count" -gt 10 ]; then
        pass_msg "GTDB-Tk database contains files: $gtdb_count files"
    else
        warn_msg "GTDB-Tk database folder exists but has very few files: $gtdb_count"
    fi
else
    fail_msg "GTDB-Tk database folder missing: $GTDBTK_DB"
fi

echo
echo "GTDBTK_DATA_PATH check:"
if [ "${GTDBTK_DATA_PATH:-}" = "$GTDBTK_DB" ]; then
    pass_msg "GTDBTK_DATA_PATH is correctly set: $GTDBTK_DATA_PATH"
elif [ -z "${GTDBTK_DATA_PATH:-}" ]; then
    warn_msg "GTDBTK_DATA_PATH is not set in this shell"
    echo "Suggested export:"
    echo "  export GTDBTK_DATA_PATH=$GTDBTK_DB"
else
    warn_msg "GTDBTK_DATA_PATH is set but points elsewhere: $GTDBTK_DATA_PATH"
    echo "Expected:"
    echo "  $GTDBTK_DB"
fi

echo
echo "CheckM2 database basic check:"
if [ -d "$CHECKM2_DB" ]; then
    checkm2_count=$(find "$CHECKM2_DB" -type f 2>/dev/null | wc -l)
    if [ "$checkm2_count" -gt 0 ]; then
        pass_msg "CheckM2 database contains files: $checkm2_count files"
    else
        warn_msg "CheckM2 database folder exists but appears empty"
    fi
else
    fail_msg "CheckM2 database folder missing: $CHECKM2_DB"
fi

echo
echo "DRAM database basic check:"
if [ -d "$DRAM_DB" ]; then
    dram_count=$(find "$DRAM_DB" -type f 2>/dev/null | wc -l)
    if [ "$dram_count" -gt 0 ]; then
        pass_msg "DRAM database folder contains files: $dram_count files"
    else
        warn_msg "DRAM database folder exists but appears empty"
    fi
else
    fail_msg "DRAM database folder missing: $DRAM_DB"
fi

echo
echo "DRAM config check:"
if command -v conda >/dev/null 2>&1; then
    if conda run -n dram_env bash -c "DRAM-setup.py print_config" >/dev/null 2>&1; then
        pass_msg "DRAM configuration can be printed"
        echo
        echo "Important DRAM config lines:"
        conda run -n dram_env bash -c "DRAM-setup.py print_config | grep -Ei 'kofam|pfam|dbcan|merops|genome summary|module step|etc|function heatmap|amg|database'" 2>/dev/null || warn_msg "Could not grep DRAM config details"
    else
        warn_msg "DRAM-setup.py print_config failed. DRAM may not be fully configured"
    fi
else
    warn_msg "Skipping DRAM config check because conda is unavailable"
fi

###############################################################################
# 10. LOG FILE CHECK
###############################################################################

section "10. LOG FILE CHECK"

check_dir "$PROJECT/logs" "Log folder"

if [ -d "$PROJECT/logs" ]; then
    echo
    echo "Recent log files:"
    find "$PROJECT/logs" -type f -printf "%TY-%Tm-%Td %TH:%TM  %p\n" 2>/dev/null | sort | tail -20
fi

###############################################################################
# 11. PERMISSION CHECK
###############################################################################

section "11. PERMISSION CHECK"

if [ -w "$PROJECT" ]; then
    pass_msg "Project folder is writable"
else
    fail_msg "Project folder is not writable"
fi

if [ -w "$PROJECT/results" ]; then
    pass_msg "Results folder is writable"
else
    fail_msg "Results folder is not writable"
fi

if [ -w "$PROJECT/logs" ]; then
    pass_msg "Logs folder is writable"
else
    fail_msg "Logs folder is not writable"
fi

if [ -w "$PROJECT/scripts" ]; then
    pass_msg "Scripts folder is writable"
else
    warn_msg "Scripts folder is not writable"
fi

###############################################################################
# 12. FINAL SUMMARY
###############################################################################

section "12. FINAL SUMMARY"

echo -e "${GREEN}Passed checks : $PASS_COUNT${NC}"
echo -e "${YELLOW}Warnings      : $WARN_COUNT${NC}"
echo -e "${RED}Missing/Fail  : $FAIL_COUNT${NC}"

echo
if [ "$FAIL_COUNT" -eq 0 ]; then
    echo -e "${GREEN}Overall status: READY${NC}"
    echo "The project-level setup looks ready for running samples."
elif [ "$FAIL_COUNT" -le 5 ]; then
    echo -e "${YELLOW}Overall status: MOSTLY READY, BUT CHECK MISSING ITEMS${NC}"
    echo "Some components are missing. Review them before running many samples."
else
    echo -e "${RED}Overall status: NOT READY${NC}"
    echo "Several required components are missing. Fix them before running the pipeline."
fi

echo
echo "Environment map used by this project:"
echo "  01_read_qc.sh                    -> shotgun_qc"
echo "  02_assembly.sh                   -> shotgun_assembly"
echo "  03_gene_prediction.sh            -> shotgun_gene"
echo "  04_cdhit.sh                      -> shotgun_gene"
echo "  05_rgi_arg_detection.sh          -> shotgun_arg"
echo "  06_prepare_metawrap_reads.sh     -> metawrap-env"
echo "  07_metawrap_binning.sh           -> metawrap-env"
echo "  08_bin_refinement.sh             -> metawrap-env"
echo "  09_checkm2.sh                    -> checkm2_env"
echo "  10_gtdbtk.sh                     -> shotgun_gtdbtk"
echo "  11_dram_annotation.sh            -> dram_env"
echo "  12_arg_contig_bin_table.sh       -> shotgun_tables"
echo "  13_mag_arg_taxonomy_table.sh     -> shotgun_tables"
echo "  14_dram_pathway_table.sh         -> shotgun_tables"
echo "  15_final_integrated_table.sh     -> shotgun_tables"

echo
echo "Next step after this setup passes:"
echo "  bash scripts/master_script.sh"
echo
echo "Or run sample-specific scripts from:"
echo "  01_read_qc.sh onward"

echo
echo "Setup confirmation completed."
echo "===================================================================="