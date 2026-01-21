#!/bin/bash -l
# THIS SCRIPT IS PROVIDED AS A SUGGESTION OF HOW TO RUN THE EXPERIMENT
# SOME ELEMENTS HAVE TO BE TWEAKED DEPENDING ON THE ENVIRONMENT WHERE THIS IS RUN
#
# ARGUMENTS:
#   $1. Number of OMP threads
#
# USAGE INSTRUCTIONS:
#    1. If you use MPI, check your MPI and MPI.jl installation, use the adequate launcher (mpirun, srun etc.)
#    2. Set up the environment variables of this script following the instruction at the comment over their definition.
#    3. If using more than one mpi rank, the source file has to be transformed first and then its output executed here instead of "transform.jl" more info at the end of file.

# Check if number of processes is provided
if [ $# -eq 0 ]; then
    echo "Error: Please provide the number of processes as an argument"
    echo "Usage: run_perftest.sh <number_of_processes>"
    exit 1
fi

# Example of modules to load for this experiment in case of running with slurm
module load julia


# This should not need to be touched
export OMP_NUM_THREADS=$1
export JULIA_PROJECT="."

# Use the provided argument for number of processes
srun -n 1 $HOME/.juliaup/bin/julia -t $1 --optimize=3 --check-bounds=no transform.jl EXP_test_halo_thr.jl




# WITH MORE THAN ONE MPI RANK (not used on the official experiment):
# Run the following command on the terminal:
#
# julia -e "using Pkg;Pkg.instantiate();using PerfTest;PerfTest.toggleMPI();@info \"Transforming expression\";expr = PerfTest.transform(\"EXP_test_halo.jl\");@info \"Saving at ./test.jl\";PerfTest.saveExprAsFile(expr, \"test.jl\")"
#
# Then execute the this script but, in the srun command, instead of taking transform.jl as the executed file, used the generated "test.jl"
