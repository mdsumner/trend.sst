#!/bin/bash --login
## Daily refresh of trend.sst: the sitrep "update" steps in one allocation.
## Run by scrontab (see scrontab.txt at the repo root), or by hand from
## the repo root:
##   sbatch --cpus-per-task=16 --mem=96G --time=03:00:00 data-raw/daily.sh
## Steps, in order:
##   1. drop the newest 10 GHRSST sums (MUR provisional tail, recomputed)
##   2. GHRSST backfill + publish
##   3. OISST catalog + backfill + publish
##   4. site export (commit + push of docs/data)
## A failed step is reported and the next one still runs; the site export
## runs last and refuses to publish a one-source export on its own.

cd "${SLURM_SUBMIT_DIR:-$PWD}"
## the step scripts cd to SLURM_SUBMIT_DIR; pin it to the repo root
export SLURM_SUBMIT_DIR="$PWD"
export SST_WORKERS=${SST_WORKERS:-${SLURM_CPUS_PER_TASK:-8}}
echo "trend.sst daily: $(date -u +%FT%TZ) in $PWD, $SST_WORKERS workers"

status=0

if [ -d sums/ghrsst ]; then
  ls sums/ghrsst | sort | tail -10 | sed 's|^|sums/ghrsst/|' | xargs -r rm -f
fi

SST_SOURCE=ghrsst bash data-raw/backfill.sh || { echo "ghrsst backfill FAILED" >&2; status=1; }
SST_SOURCE=oisst  bash data-raw/backfill.sh || { echo "oisst backfill FAILED" >&2; status=1; }
bash data-raw/export_site.sh                 || { echo "site export FAILED" >&2; status=1; }

echo "trend.sst daily: done $(date -u +%FT%TZ), status $status"
exit $status
