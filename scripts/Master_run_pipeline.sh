#!/bin/bash

set -uo pipefail

# ==========================================================
# MASTER SCRIPT: Resume-capable shotgun metagenomic pipeline
# ==========================================================
#
# This script:
#   1. Opens as an interactive terminal form.
#   2. Asks for the sample ID.
#   3. Runs each numbered pipeline script in order.
#   4. Reports every step.
#   5. Creates checkpoint files after successful steps.
#   6. Skips completed steps when rerun.
#   7. Resumes from the failed/incomplete step.
#   8. Saves a master log and step-wise status report.
#
# Important:
# This master script resumes BETWEEN scripts.
# If an individual script fails halfway, that script will rerun from its beginning
# unless that script has its own internal checkpointing.
# ==========================================================


# ==========================================================
# PROJECT SETTINGS
# ==========================================================

PROJECT="/mnt/e/kshiteeja/shotgun_project"
SCRIPTS_DIR="$PROJECT/scripts"
LOG_DIR="$PROJECT/logs/master"
CHECKPOINT_DIR="$PROJECT/logs/master/checkpoints"

mkdir -p "$LOG_DIR"
mkdir -p "$CHECKPOINT_DIR"


# ==========================================================
# INTERACTIVE FORM
# ==========================================================

clear

echo "======================================================"
echo "        SHOTGUN METAGENOMIC PIPELINE MASTER RUNNER"
echo "======================================================"
echo
echo "Project folder:"
echo "$PROJECT"
echo
echo "This script will run the full workflow step-by-step."
echo "Completed steps will be skipped automatically on rerun."
echo

# ----------------------------------------------------------
# Sample ID input
# ----------------------------------------------------------

if [ "${1:-}" != "" ]; then
    DEFAULT_SAMPLE_ID="$1"
else
    DEFAULT_SAMPLE_ID="ERR12510647"
fi

read -rp "Enter Sample ID [default: $DEFAULT_SAMPLE_ID]: " USER_SAMPLE_ID

if [ "$USER_SAMPLE_ID" = "" ]; then
    SAMPLE_ID="$DEFAULT_SAMPLE_ID"
else
    SAMPLE_ID="$USER_SAMPLE_ID"
fi

echo
echo "Selected sample ID: $SAMPLE_ID"
echo

# ----------------------------------------------------------
# Resume or force rerun choice
# ----------------------------------------------------------

echo "Choose run mode:"
echo
echo "  1) Resume mode       - skip completed steps and continue from incomplete/failed step"
echo "  2) Force rerun mode  - rerun all steps from beginning"
echo

read -rp "Enter choice [default: 1]: " RUN_MODE

if [ "$RUN_MODE" = "2" ]; then
    FORCE_RERUN="yes"
else
    FORCE_RERUN="no"
fi

echo
echo "Run mode: $([ "$FORCE_RERUN" = "yes" ] && echo "FORCE RERUN" || echo "RESUME")"
echo

# ----------------------------------------------------------
# Final confirmation
# ----------------------------------------------------------

echo "======================================================"
echo "RUN CONFIRMATION"
echo "======================================================"
echo "Sample ID        : $SAMPLE_ID"
echo "Project folder   : $PROJECT"
echo "Scripts folder   : $SCRIPTS_DIR"
echo "Log folder       : $LOG_DIR"
echo "Checkpoint folder: $CHECKPOINT_DIR"
echo "Force rerun      : $FORCE_RERUN"
echo "======================================================"
echo

read -rp "Start pipeline now? Type yes to continue: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo
    echo "Pipeline cancelled by user."
    exit 0
fi


# ==========================================================
# LOG FILES
# ==========================================================

RUN_TIME=$(date +%Y%m%d_%H%M%S)

MASTER_LOG="$LOG_DIR/${SAMPLE_ID}_master_pipeline_${RUN_TIME}.log"
STATUS_REPORT="$LOG_DIR/${SAMPLE_ID}_pipeline_status_${RUN_TIME}.tsv"

LATEST_STATUS_REPORT="$LOG_DIR/${SAMPLE_ID}_pipeline_status_latest.tsv"
LATEST_MASTER_LOG="$LOG_DIR/${SAMPLE_ID}_master_pipeline_latest.log"


# ==========================================================
# HEADER
# ==========================================================

echo "==================================================" | tee -a "$MASTER_LOG"
echo "SHOTGUN METAGENOMIC PIPELINE MASTER SCRIPT" | tee -a "$MASTER_LOG"
echo "==================================================" | tee -a "$MASTER_LOG"
echo "Sample ID        : $SAMPLE_ID" | tee -a "$MASTER_LOG"
echo "Project folder   : $PROJECT" | tee -a "$MASTER_LOG"
echo "Scripts folder   : $SCRIPTS_DIR" | tee -a "$MASTER_LOG"
echo "Log folder       : $LOG_DIR" | tee -a "$MASTER_LOG"
echo "Checkpoint folder: $CHECKPOINT_DIR" | tee -a "$MASTER_LOG"
echo "Master log       : $MASTER_LOG" | tee -a "$MASTER_LOG"
echo "Status report    : $STATUS_REPORT" | tee -a "$MASTER_LOG"
echo "Start time       : $(date)" | tee -a "$MASTER_LOG"
echo "Force rerun      : $FORCE_RERUN" | tee -a "$MASTER_LOG"
echo "==================================================" | tee -a "$MASTER_LOG"
echo | tee -a "$MASTER_LOG"


# ==========================================================
# SAFETY CHECKS
# ==========================================================

if [ ! -d "$PROJECT" ]; then
    echo "ERROR: Project folder not found: $PROJECT" | tee -a "$MASTER_LOG"
    exit 1
fi

if [ ! -d "$SCRIPTS_DIR" ]; then
    echo "ERROR: Scripts folder not found: $SCRIPTS_DIR" | tee -a "$MASTER_LOG"
    exit 1
fi


# ==========================================================
# STATUS REPORT HEADER
# ==========================================================

echo -e "sample_id\tstep_number\tstep_name\tscript_name\trequired_status\tpipeline_status\tstart_time\tend_time\truntime_seconds\tlog_file" > "$STATUS_REPORT"


# ==========================================================
# FUNCTION TO RUN EACH STEP
# ==========================================================

run_step() {
    STEP_NUMBER="$1"
    STEP_NAME="$2"
    SCRIPT_NAME="$3"
    REQUIRED="$4"

    SCRIPT_PATH="$SCRIPTS_DIR/$SCRIPT_NAME"
    STEP_LOG="$LOG_DIR/${SAMPLE_ID}_${STEP_NUMBER}_${SCRIPT_NAME%.sh}.log"

    DONE_FILE="$CHECKPOINT_DIR/${SAMPLE_ID}_${STEP_NUMBER}_${SCRIPT_NAME%.sh}.done"
    FAILED_FILE="$CHECKPOINT_DIR/${SAMPLE_ID}_${STEP_NUMBER}_${SCRIPT_NAME%.sh}.failed"

    echo | tee -a "$MASTER_LOG"
    echo "--------------------------------------------------" | tee -a "$MASTER_LOG"
    echo "STEP $STEP_NUMBER: $STEP_NAME" | tee -a "$MASTER_LOG"
    echo "--------------------------------------------------" | tee -a "$MASTER_LOG"
    echo "Script          : $SCRIPT_NAME" | tee -a "$MASTER_LOG"
    echo "Required status : $REQUIRED" | tee -a "$MASTER_LOG"
    echo "Step log        : $STEP_LOG" | tee -a "$MASTER_LOG"
    echo "Done checkpoint : $DONE_FILE" | tee -a "$MASTER_LOG"
    echo "Failed marker   : $FAILED_FILE" | tee -a "$MASTER_LOG"
    echo "--------------------------------------------------" | tee -a "$MASTER_LOG"

    # ------------------------------------------------------
    # Resume logic
    # ------------------------------------------------------

    if [ -f "$DONE_FILE" ] && [ "$FORCE_RERUN" != "yes" ]; then
        echo "STATUS: SKIPPED" | tee -a "$MASTER_LOG"
        echo "Reason: This step already completed in an earlier run." | tee -a "$MASTER_LOG"

        echo -e "${SAMPLE_ID}\t${STEP_NUMBER}\t${STEP_NAME}\t${SCRIPT_NAME}\t${REQUIRED}\tSKIPPED_ALREADY_DONE\tNA\tNA\t0\t${STEP_LOG}" >> "$STATUS_REPORT"

        return 0
    fi

    # ------------------------------------------------------
    # Check whether script exists
    # ------------------------------------------------------

    if [ ! -f "$SCRIPT_PATH" ]; then
        echo "STATUS: FAILED" | tee -a "$MASTER_LOG"
        echo "Reason: Script not found." | tee -a "$MASTER_LOG"
        echo "Missing script path: $SCRIPT_PATH" | tee -a "$MASTER_LOG"

        touch "$FAILED_FILE"

        echo -e "${SAMPLE_ID}\t${STEP_NUMBER}\t${STEP_NAME}\t${SCRIPT_NAME}\t${REQUIRED}\tFAILED_SCRIPT_MISSING\tNA\t$(date)\t0\tNA" >> "$STATUS_REPORT"

        if [ "$REQUIRED" = "required" ]; then
            echo "This is a required step. Pipeline stopped." | tee -a "$MASTER_LOG"
            exit 1
        else
            echo "This is an optional step. Pipeline will continue." | tee -a "$MASTER_LOG"
            return 0
        fi
    fi

    chmod +x "$SCRIPT_PATH"

    # Remove old failed marker before attempting rerun
    rm -f "$FAILED_FILE"

    START_TIME_READABLE=$(date)
    START_TIME_SECONDS=$(date +%s)

    echo "STATUS: RUNNING" | tee -a "$MASTER_LOG"
    echo "Started at: $START_TIME_READABLE" | tee -a "$MASTER_LOG"

    bash "$SCRIPT_PATH" "$SAMPLE_ID" > "$STEP_LOG" 2>&1
    STATUS=$?

    END_TIME_READABLE=$(date)
    END_TIME_SECONDS=$(date +%s)
    RUNTIME_SECONDS=$((END_TIME_SECONDS - START_TIME_SECONDS))

    if [ "$STATUS" -eq 0 ]; then
        echo "STATUS: SUCCESS" | tee -a "$MASTER_LOG"
        echo "Finished at: $END_TIME_READABLE" | tee -a "$MASTER_LOG"
        echo "Runtime seconds: $RUNTIME_SECONDS" | tee -a "$MASTER_LOG"

        touch "$DONE_FILE"
        rm -f "$FAILED_FILE"

        echo -e "${SAMPLE_ID}\t${STEP_NUMBER}\t${STEP_NAME}\t${SCRIPT_NAME}\t${REQUIRED}\tSUCCESS\t${START_TIME_READABLE}\t${END_TIME_READABLE}\t${RUNTIME_SECONDS}\t${STEP_LOG}" >> "$STATUS_REPORT"

        return 0

    else
        echo "STATUS: FAILED" | tee -a "$MASTER_LOG"
        echo "Exit code: $STATUS" | tee -a "$MASTER_LOG"
        echo "Failed at: $END_TIME_READABLE" | tee -a "$MASTER_LOG"
        echo "Runtime before failure: $RUNTIME_SECONDS seconds" | tee -a "$MASTER_LOG"
        echo "Check this step log:" | tee -a "$MASTER_LOG"
        echo "$STEP_LOG" | tee -a "$MASTER_LOG"

        touch "$FAILED_FILE"

        echo -e "${SAMPLE_ID}\t${STEP_NUMBER}\t${STEP_NAME}\t${SCRIPT_NAME}\t${REQUIRED}\tFAILED_EXIT_CODE_${STATUS}\t${START_TIME_READABLE}\t${END_TIME_READABLE}\t${RUNTIME_SECONDS}\t${STEP_LOG}" >> "$STATUS_REPORT"

        if [ "$REQUIRED" = "required" ]; then
            echo | tee -a "$MASTER_LOG"
            echo "This is a required step. Pipeline stopped." | tee -a "$MASTER_LOG"
            echo | tee -a "$MASTER_LOG"
            echo "After fixing the issue, run this master script again:" | tee -a "$MASTER_LOG"
            echo "bash $SCRIPTS_DIR/MASTER_run_pipeline.sh" | tee -a "$MASTER_LOG"
            echo | tee -a "$MASTER_LOG"
            echo "Completed steps will be skipped automatically." | tee -a "$MASTER_LOG"

            exit 1
        else
            echo "This is an optional step. Pipeline will continue." | tee -a "$MASTER_LOG"
            return 0
        fi
    fi
}


# ==========================================================
# PIPELINE STEPS
# ==========================================================

echo | tee -a "$MASTER_LOG"
echo "Starting pipeline steps..." | tee -a "$MASTER_LOG"
echo | tee -a "$MASTER_LOG"


# ----------------------------------------------------------
# 01. Read quality control
# ----------------------------------------------------------

run_step "01" "Read quality control" \
         "01_read_qc.sh" \
         "required"


# ----------------------------------------------------------
# 02. Assembly
# ----------------------------------------------------------

run_step "02" "Metagenome assembly" \
         "02_assembly.sh" \
         "required"


# ----------------------------------------------------------
# 03. Gene prediction
# ----------------------------------------------------------

run_step "03" "Gene prediction" \
         "03_gene_prediction.sh" \
         "required"


# ----------------------------------------------------------
# 04. CD-HIT clustering
# ----------------------------------------------------------

run_step "04" "Gene clustering using CD-HIT" \
         "04_cdhit.sh" \
         "required"


# ----------------------------------------------------------
# 05. ARG detection
# ----------------------------------------------------------

run_step "05" "ARG detection using RGI/CARD" \
         "05_rgi_arg_detection.sh" \
         "required"


# ----------------------------------------------------------
# 06. Prepare reads for MetaWRAP
# ----------------------------------------------------------

run_step "06" "Prepare reads for MetaWRAP binning" \
         "06_prepare_metawrap_reads.sh" \
         "required"


# ----------------------------------------------------------
# 07. MetaWRAP binning
# ----------------------------------------------------------

run_step "07" "Genome binning using MetaWRAP" \
         "07_metawrap_binning.sh" \
         "required"


# ----------------------------------------------------------
# 08. Bin refinement
# ----------------------------------------------------------

run_step "08" "MAG bin refinement" \
         "08_bin_refinement.sh" \
         "required"


# ----------------------------------------------------------
# 09. CheckM2 quality assessment
# ----------------------------------------------------------

run_step "09" "MAG quality assessment using CheckM2" \
         "09_checkm2.sh" \
         "required"


# ----------------------------------------------------------
# 10. GTDB-Tk taxonomy
# ----------------------------------------------------------

run_step "10" "MAG taxonomy using GTDB-Tk" \
         "10_gtdbtk.sh" \
         "required"


# ----------------------------------------------------------
# 11. DRAM annotation
# ----------------------------------------------------------

run_step "11" "MAG functional annotation using DRAM" \
         "11_dram_annotation.sh" \
         "required"


# ----------------------------------------------------------
# 12. DRAM distillation
# ----------------------------------------------------------

run_step "12" "DRAM metabolic distillation" \
         "12_dram_distill.sh" \
         "required"


# ----------------------------------------------------------
# 13. Table 1
# ----------------------------------------------------------

run_step "13" "Final Table 1: ARG gene to contig to MAG mapping" \
         "13_table1_arg_contig_bin.sh" \
         "optional"


# ----------------------------------------------------------
# 14. Table 2
# ----------------------------------------------------------

run_step "14" "Final Table 2: MAG taxonomy and DRAM metabolic table" \
         "14_table2_mag_taxonomy_dram.sh" \
         "optional"


# ----------------------------------------------------------
# 15. Final integrated table
# ----------------------------------------------------------

run_step "15" "Final integrated ARG-taxonomy-bioremediation table" \
         "15_final_integrated_table.sh" \
         "optional"


# ==========================================================
# FINAL SUMMARY
# ==========================================================

cp "$STATUS_REPORT" "$LATEST_STATUS_REPORT"
cp "$MASTER_LOG" "$LATEST_MASTER_LOG"

echo | tee -a "$MASTER_LOG"
echo "==================================================" | tee -a "$MASTER_LOG"
echo "PIPELINE FINISHED SUCCESSFULLY" | tee -a "$MASTER_LOG"
echo "==================================================" | tee -a "$MASTER_LOG"
echo "Sample ID          : $SAMPLE_ID" | tee -a "$MASTER_LOG"
echo "End time           : $(date)" | tee -a "$MASTER_LOG"
echo "Master log         : $MASTER_LOG" | tee -a "$MASTER_LOG"
echo "Latest master log  : $LATEST_MASTER_LOG" | tee -a "$MASTER_LOG"
echo "Status report      : $STATUS_REPORT" | tee -a "$MASTER_LOG"
echo "Latest status file : $LATEST_STATUS_REPORT" | tee -a "$MASTER_LOG"
echo "==================================================" | tee -a "$MASTER_LOG"

echo
echo "Pipeline finished successfully."
echo
echo "Sample ID:"
echo "$SAMPLE_ID"
echo
echo "Master log:"
echo "$MASTER_LOG"
echo
echo "Status report:"
echo "$STATUS_REPORT"
echo
echo "To view the latest status report:"
echo "column -t -s \$'\t' $LATEST_STATUS_REPORT"
echo