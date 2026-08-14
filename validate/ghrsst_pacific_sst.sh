#!/bin/bash --login
#SBATCH --job-name=ghrsst-pacific
#SBATCH --partition=work
#SBATCH --account=pawsey1362
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=128
#SBATCH --mem=0
#SBATCH --time=08:00:00
#SBATCH --output=%x-%j.out

## exclusive + mem=0 takes the whole node and all its memory, but the R
## script only spins up SST_WORKERS daemons so it won't oversubscribe
export SST_WORKERS=96

## however you normally get R on setonix, e.g. your container:
module load singularity/4.1.0-slurm
RUN="singularity exec $MYSOFTWARE/sif_lib/gdal-r-python-extras_latest.sif"
#RUN=""

cd "$MYSCRATCH/sst"
$RUN Rscript ~/batch/sst/ghrsst_pacific_sst.R
