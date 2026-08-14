#!/bin/bash --login
#SBATCH --job-name=trend-sst-ghrsst
#SBATCH --partition=work
#SBATCH --account=pawsey1362
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=128
#SBATCH --mem=0
#SBATCH --time=24:00:00
#SBATCH --output=%x-%j.out

## banded accumulation keeps per-worker memory under ~1 GB, so wide is
## fine; the run is network-bound on the COG reads
export SST_WORKERS=64

module load singularity/4.1.0-slurm
RUN="singularity exec $MYSOFTWARE/sif_lib/gdal-r-python-extras_latest.sif"



cd "$SLURM_SUBMIT_DIR"
$RUN Rscript backfill_ghrsst.R
