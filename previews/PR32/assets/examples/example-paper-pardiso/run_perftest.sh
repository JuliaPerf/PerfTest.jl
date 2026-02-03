#!/bin/bash
# THIS SCRIPT IS PROVIDED AS A SUGGESTION OF HOW TO RUN THE EXPERIMENT
# SOME ELEMENTS HAVE TO BE TWEAKED DEPENDING ON THE ENVIRONMENT WHERE THIS IS RUN
#
# USAGE INSTRUCTIONS:
#   1. Download the panua pardiso dynamic library (.so file) from the official source at panua.ch. Follow the official license configuration guidelines.
#   2. Make sure you have a Julia installation and a C compiler suite for BOTH x86 AND arm
#   3. Set up the environment variables of this script following the instruction at the comment over their definition.
#   4. Download the matrices used by the experiment at , put the contents of the zip file in the directory where this file is.
#   5. Run the script, you will get a set of roofline experiments over the computation of different linear systems, see pardisotest.jl for more info


# Detect architecture, useful if you want to make conditional setups depending on the architecture
ARCH=$(uname -m)

# This experiment is based on a single thread
export OMP_NUM_THREADS=1

# Example of modules to load for this experiment in case of running with slurm
# module load intel intel-oneapi-mkl intel-tbb julia

# IMPORTANT! The location of the pardiso library folder
export JULIA_PARDISO=""
# Additional libraries you might need (or not) depending on your installation
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH
# This should not need to be touched
export JULIA_PROJECT="."

# You might need (or not) to change the julia executable path to get the one you are interested in using
julia -t 1 transform.jl
