#!/bin/bash

###############################################################################
# 00_setup_project.sh
#
# Purpose:
#   One-time project-level setup + confirmation script for the shotgun
#   metagenomics pipeline.
#
# This script:
#   1. Creates required base project folders
#   2. Checks conda availability
#   3. Checks required conda environments
#   4. Checks major tools inside each environment
#   5. Checks database folders
#   6. Checks script files
#   7. Checks permissions and disk space
#
# Important:
#   This script is NOT sample-specific.
#   Run it once after setting up the project.
#
# Usage:
#   bash scripts/00_setup_project.sh
#
###############################################################################

set -u

###############################################################################
# USER CONFIGURATION
###############################################################################

PDB_ROOT="$PROJECT/Databases"

KRAKEN2_DB="$DB_ROOT/kraken2"
GTDBTK_DB="$DB_ROOT/GTDBTK/release232"
CHECKM2_DB="$DB_ROOT/checkm2_database"
DRAM_DB="$DB_ROOT/DRAM"

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
    echo -e "${RED}[MISSING]${NC} $1"
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
        pass_msg "$label exists: $path"
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

check_tool_version_in_env() {
    local env="$1"
    local tool="$2"
    local version_cmd="$3"

    if command -v conda >/dev/null 2>&1; then
        if conda run -n "$env" bash -c "command -v $tool >/dev/null 2>&1" >/dev/null 2>&1; then
            version_output=$(conda run -n "$env" bash -c "$version_cmd" 2>&1 | head -n 1)
            pass_msg "$tool found in $env | $version_output"
        else
            fail_msg "$tool missing in environment: $env"
        fi
    else
        fail_msg "Cannot check $tool because conda is not available"
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
    "Databases"
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
    "config"
    "Notes"
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
)

for script in "${EXPECTED_SCRIPTS[@]}"; do
    if [ -f "$PROJECT/scripts/$script" ]; then
        pass_msg "Script found: scripts/$script"

        if [ -x "$PROJECT/scripts/$script" ]; then
            pass_msg "Script is executable: scripts/$script"
        else
            warn_msg "Script is not executable. Run: chmod +x $PROJECT/scripts/$script"
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
check_tool_in_env "shotgun_qc" "fastqc"
check_tool_in_env "shotgun_qc" "multiqc"

echo
echo "Assembly tools:"
check_tool_version_in_env "shotgun_assembly" "megahit" "megahit --version"

echo
echo "Gene prediction tools:"
check_tool_in_env "shotgun_gene" "prodigal"

echo
echo "Clustering tools:"
check_tool_in_env "shotgun_gene" "cd-hit"

echo
echo "ARG detection tools:"
check_tool_in_env "shotgun_arg" "rgi"

echo
echo "Binning tools:"
check_tool_in_env "metawrap-env" "metawrap"
check_tool_in_env "metawrap-env" "kraken2"
check_tool_in_env "metawrap-env" "metabat2"
check_tool_in_env "metawrap-env" "run_MaxBin.pl"

echo
echo "Bin quality tools:"
check_tool_in_env "metawrap-env" "checkm"
check_tool_in_env "metawrap-env" "CheckM2"

echo
echo "Taxonomy tools:"
check_tool_version_in_env "shotgun_gtdbtk" "gtdbtk" "gtdbtk --version"

echo
echo "Functional annotation tools:"
check_tool_in_env "dram_env" "DRAM.py"
check_tool_in_env "dram_env" "DRAM-setup.py"

echo
echo "Table-generation tools:"
check_tool_in_env "shotgun_tables" "python"
check_tool_in_env "shotgun_tables" "python3"

###############################################################################
# 7. DATABASE CHECK
###############################################################################

section "7. DATABASE CHECK"

check_dir "$DB_ROOT" "Database root"
check_dir "$KRAKEN2_DB" "Kraken2 database"
check_dir "$GTDBTK_DB" "GTDB-Tk database"
check_dir "$CHECKM2_DB" "CheckM2 database"
check_dir "$DRAM_DB" "DRAM database folder"

echo
echo "Database size overview:"
du -sh "$DB_ROOT"/* 2>/dev/null || warn_msg "Could not calculate database folder sizes"

###############################################################################
# 8. DATABASE-SPECIFIC FILE CHECKS
###############################################################################

section "8. DATABASE-SPECIFIC FILE CHECKS"

echo
echo "Kraken2 database files:"
check_optional_file "$KRAKEN2_DB/hash.k2d" "Kraken2 hash.k2d"
check_optional_file "$KRAKEN2_DB/opts.k2d" "Kraken2 opts.k2d"
check_optional_file "$KRAKEN2_DB/taxo.k2d" "Kraken2 taxo.k2d"

echo
echo "GTDB-Tk database basic check:"
if [ -d "$GTDBTK_DB" ]; then
    gtdb_count=$(find "$GTDBTK_DB" -type f 2>/dev/null | wc -l)
    if [ "$gtdb_count" -gt 10 ]; then
        pass_msg "GTDB-Tk database contains files: $gtdb_count files"
    else
        warn_msg "GTDB-Tk database folder exists but has very few files: $gtdb_count"
    fi
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
fi

###############################################################################
# 9. LOG FILE CHECK
###############################################################################

section "9. LOG FILE CHECK"

check_dir "$PROJECT/logs" "Log folder"

if [ -d "$PROJECT/logs" ]; then
    echo
    echo "Recent log files:"
    find "$PROJECT/logs" -type f -printf "%TY-%Tm-%Td %TH:%TM  %p\n" 2>/dev/null | sort | tail -20
fi

###############################################################################
# 10. PERMISSION CHECK
###############################################################################

section "10. PERMISSION CHECK"

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

###############################################################################
# 11. FINAL SUMMARY
###############################################################################

section "11. FINAL SUMMARY"

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
echo "Next step after this setup passes:"
echo "  Run sample-specific scripts from 01_read_qc.sh onward."

echo
echo "Setup confirmation completed."
echo "===================================================================="