#!/bin/bash

PROJECT=/mnt/e/kshiteeja/shotgun_project
DB_ROOT=/mnt/e/metawrap_databases
KRAKEN2_DB=/mnt/e/metawrap_databases/kraken2

echo "=============================="
echo "SHOTGUN PROJECT SETUP CHECK"
echo "=============================="

echo
echo "Project folder:"
[ -d "$PROJECT" ] && echo "OK: $PROJECT" || echo "MISSING: $PROJECT"

echo
echo "Main folders:"
for d in data/raw data/clean data/databases results/qc results/assembly results/gene_prediction results/CDHIT results/ARGs results/binning results/bin_refinement results/final_tables scripts logs config; do
    [ -d "$PROJECT/$d" ] && echo "OK: $d" || echo "MISSING: $d"
done

echo
echo "Conda:"
conda --version

echo
echo "Conda environments:"
for env in shotgun_qc shotgun_assembly shotgun_gene shotgun_arg metawrap-env shotgun_tables; do
    if conda env list | awk '{print $1}' | grep -qx "$env"; then
        echo "OK: $env"
    else
        echo "MISSING: $env"
    fi
done

echo
echo "Database root:"
[ -d "$DB_ROOT" ] && echo "OK: $DB_ROOT" || echo "MISSING: $DB_ROOT"

echo
echo "Kraken2 database:"
if [ -f "$KRAKEN2_DB/hash.k2d" ] && [ -f "$KRAKEN2_DB/opts.k2d" ] && [ -f "$KRAKEN2_DB/taxo.k2d" ]; then
    echo "OK: $KRAKEN2_DB"
else
    echo "MISSING or incomplete: $KRAKEN2_DB"
fi

echo
echo "Setup check complete."