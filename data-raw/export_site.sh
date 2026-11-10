#!/bin/bash --login
#SBATCH --job-name=trend-sst-site
#SBATCH --partition=work
#SBATCH --account=pawsey1362
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=01:00:00
#SBATCH --output=%x-%j.out

## Regenerate docs/data from the LOCAL sums on scratch (no cache pull)
## and commit. Submit from the repo root after a backfill:
##   sbatch data-raw/export_site.sh
## Setonix modules: singularity/4.1.0-slurm needs pawseyenv/2024.05 (the
## default pawseyenv moved on), and a non-login shell needs Lmod first
if ! type module >/dev/null 2>&1; then _u=${-//[^u]/}; set +u; source /etc/profile; [ -n "$_u" ] && set -u; fi
module load pawseyenv/2024.05 singularity/4.1.0-slurm
command -v singularity >/dev/null || { echo "singularity not found after module load" >&2; exit 1; }
RUN="singularity exec $MYSOFTWARE/sif_lib/gdal-r-python-extras_2026-10-25.sif"
export R_LIBS_USER=${R_LIBS_USER:-$MYSOFTWARE/r-lib}

cd "$SLURM_SUBMIT_DIR"
## the exporter's cache layout IS the repo root (sums/ + s2_registry.parquet)
$RUN Rscript data-raw/export_site.R . || { echo "export FAILED" >&2; exit 1; }

## modes page: EOFs of the monthly exports just written (numpy only);
## GHRSST is restricted to cells OISST has (MUR covers lakes worldwide).
## A failure leaves the previous eof-*.json in place.
$RUN python3 data-raw/eof.py docs/data oisst degC 6 \
  || echo "WARNING: eof.py oisst FAILED" >&2
$RUN python3 data-raw/eof.py docs/data ghrsst degC 6 oisst \
  || echo "WARNING: eof.py ghrsst FAILED" >&2

## refuse to publish a one-source export when both sums exist
for src in oisst ghrsst; do
  if [ -d "sums/$src" ] && ! grep -q "\"$src\"" docs/data/status.json; then
    echo "export missing $src though sums/$src exists -- NOT committing" >&2
    exit 1
  fi
done

git add docs/data \
  && git commit -m "site data: regenerated from sums ($(date -u +%F))" \
  && git push origin main
