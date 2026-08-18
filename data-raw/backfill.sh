#!/bin/bash --login
#SBATCH --job-name=trend-sst
#SBATCH --partition=work
#SBATCH --account=pawsey1362
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=128
#SBATCH --mem=0
#SBATCH --time=24:00:00
#SBATCH --output=%x-%j.out

## submit FROM THE REPO ROOT:
##   SST_SOURCE=oisst  sbatch --export=ALL data-raw/backfill.sh   # dress rehearsal
##   SST_SOURCE=ghrsst sbatch --export=ALL data-raw/backfill.sh
export SST_SOURCE=${SST_SOURCE:-oisst}
export SST_WORKERS=${SST_WORKERS:-64}

module load rclone/1.68.1
module load singularity/4.1.0-slurm
RUN="singularity exec $MYSOFTWARE/sif_lib/gdal-r-python-extras_latest.sif"

## trend.sst must be installed where the container's R can see it, e.g.
## once, interactively:
##   export R_LIBS_USER=$MYSOFTWARE/r-lib
##   $RUN R CMD INSTALL .
export R_LIBS_USER=${R_LIBS_USER:-$MYSOFTWARE/r-lib}

cd "$SLURM_SUBMIT_DIR"
$RUN Rscript data-raw/backfill.R

## the bucket is the artifact's home; sync is part of the run, not a chore
#rclone sync sums/ pawsey1197:aad-derived/trend-sst/sums/
#rclone sync mapping/ pawsey1197:aad-derived/trend-sst/mapping/

rclone copy --checksum sums/ pawsey1197:aad-derived/trend-sst/sums/ \
  || echo "WARNING: sums copy FAILED" >&2
rclone copy --checksum mapping/ pawsey1197:aad-derived/trend-sst/mapping/ \
  || echo "WARNING: mapping copy FAILED" >&2
