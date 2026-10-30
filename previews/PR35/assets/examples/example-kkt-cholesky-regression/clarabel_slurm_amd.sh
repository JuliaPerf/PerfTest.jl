#!/bin/bash
#SBATCH --job-name=clarabel
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --output=clarabel-%j.out
#SBATCH --time=6:00:00
#SBATCH --exclusive
#SBATCH --nodelist=milan1            # Specify a particular node
#SBATCH --constraint=hwperf          # Specify a node constraint

echo "Job started on $(hostname) at $(date)"
echo "Job ID: $SLURM_JOB_ID"
echo "Nodes: $SLURM_JOB_NODELIST"
echo "----------------------------------------------------------------"

# Load modules
# module load <module_name>
#
module load likwid

# Set environment variables
# export VAR=value

# User commands
./run_demo.sh clarabel_perftest.jl

echo "----------------------------------------------------------------"
echo "Job completed at $(date)"
