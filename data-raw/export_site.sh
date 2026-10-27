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
module load singularity/4.1.0-slurm
RUN="singularity exec $MYSOFTWARE/sif_lib/gdal-r-python-extras_2026-10-25.sif"
export R_LIBS_USER=${R_LIBS_USER:-$MYSOFTWARE/r-lib}

cd "$SLURM_SUBMIT_DIR"
## the exporter's cache layout IS the repo root (sums/ + s2_registry.parquet)
$RUN Rscript data-raw/export_site.R . || { echo "export FAILED" >&2; exit 1; }

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
