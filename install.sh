#!/bin/bash

##############################################################
# Author: Nathan Culshaw
# Script: install.sh
# CAUTION:
#  - For the sake of saving credits, we do not have a 'make clean' or
#   'make realclean'. If you are wanting to recompile, either add this
#    keyword or remove the directory to reclone.
# Purpose:
#   PBS job script for building NWChem on the NCI Gadi supercomputer
#   using the Intel LLVM compiler suite (ifx/icx/icpx), Intel MPI,
#   and Intel MKL. This script automates cloning, configuration,
#   and compilation of NWChem.
#
# Usage:
#   qsub install.sh
#
# Notes:
#   - Clones repositry into current PWD. This will need to exist
#     in the same relative dir where the run.sh script is. As seen
#     provided.
#   - Runs in the copyq queue for installation tasks.
#   - Produces a full build log (build.log) for debugging.
#   - Verifies executable creation at the end of the job.
# Last Updated: 27 October 2025
##############################################################

#PBS -N nwchem_install_intel_llvm
#PBS -q copyq
#PBS -l jobFS=10GB
#PBS -l ncpus=1
#PBS -l mem=32gb
#PBS -l walltime=04:00:00
#PBS -j oe
#PBS -o build.log

path=$(pwd)

export NWCHEM_TOP=${path}/nwchem
mkdir -p $NWCHEM_TOP
echo "NWChem top directory: $NWCHEM_TOP"

# Clone repository if needed
if [ ! -d "$NWCHEM_TOP/.git" ]; then
    echo "Cloning NWChem repository..."
    git clone https://github.com/nwchemgit/nwchem $NWCHEM_TOP
else
    echo "Repository already exists, skipping clone."
fi

# Load compiler modules
echo "Loading modules..."
module purge
module load intel-compiler-llvm/2025.2.0
module load intel-mpi/2021.16.0
module load intel-mkl/2025.2.0

# print modules for purpose of debugging
echo "Modules loaded:"
module list

# Compiler settings (LLVM ICX); IFX, ICX, ICPX
export FC=ifx
export CC=icx
export CXX=icpx
export OMPI_FC=mpiifort #$FC
export OMPI_CC=mpiicc #$CC
export OMPI_CXX=mpiicpc #$CXX

# Compiler flags
export FCFLAGS="-Ofast -march=sapphirerapids -fp-model fast=2 -fopenmp -i8 -fPIC -ipo -fallow-argument-mismatch -fno-operator-overloading-check"
export CCFLAGS="-Ofast -march=sapphirerapids -fp-model fast=2 -fPIC -ipo"
export CXXFLAGS="-Ofast -march=sapphirerapids -fp-model fast=2 -fPIC -ipo"

echo "FC=$FC, CC=$CC, CXX=$CXX"
echo "FCFLAGS=$FCFLAGS"
echo "CCFLAGS=$CCFLAGS"
echo "CXXFLAGS=$CXXFLAGS"

# NWChem build options
export USE_MPI=y
export USE_OPENMP=y
export USE_GA=y
export NWCHEM_TARGET=LINUX64

export NWCHEM_MODULES="all"
export BLAS_SIZE=8
export SCALAPACK_SIZE=8

# MKL BLAS/LAPACK settings
# Threaded MKL ILP64 (Intel MPI version)
export BLASOPT="-L${MKLROOT}/lib/intel64 -Wl,--start-group \
        -lmkl_intel_ilp64 -lmkl_core -lmkl_intel_thread -Wl,--end-group \
        -liomp5 -lpthread -lm -ldl"

export BLAS_LIB="$BLASOPT"
export LAPACK_LIB="$BLASOPT"
export USE_SCALAPACK=y
export SCALAPACK_LIB="-L${MKLROOT}/lib/intel64 \
        -lmkl_scalapack_ilp64 -lmkl_blacs_intelmpi_ilp64 ${BLASOPT}"

echo "BLASOPT=$BLASOPT"
echo "SCALAPACK_LIB=$SCALAPACK_LIB"

# ARMCI SETTINGS
export ARMCI_NETWORK=MPI-PR
export EXTERNAL_ARMCI_PATH=$NWCHEM_TOP/external-armci

# Fetch NWChem tools first
cd $NWCHEM_TOP/src/tools

echo "Fetching NWChem tools..."
./get-tools-github

echo "Installing ARMCI-MPI..."
./install-armci-mpi

# Additional environment variables for Intel compilers
export INTEL_LICENSE_FILE=/apps/intel-tools/intel-compiler-llvm/2025.2.0/licensing
export LD_LIBRARY_PATH=${MKLROOT}/lib/intel64:${LD_LIBRARY_PATH}

# Build NWChem - IMPROVED
cd $NWCHEM_TOP/src

#echo "Cleaning previous build..."
#add a make clean here if you want, we found it more time consuming
#and thus just recloned repositry each time we unsuccessfully built/linked.

echo "Generating NWChem configuration..."
make nwchem_config

echo "Configuration check:"
echo "NWCHEM_TARGET: $NWCHEM_TARGET"
echo "NWCHEM_MODULES: $NWCHEM_MODULES"
echo "FC: $FC"
echo "CC: $CC"

make -j1 2>&1 | tee build.log

# Check if compilation succeeded
if [ -f $NWCHEM_TOP/bin/LINUX64/nwchem ]; then
    echo "==================== NWChem build SUCCESS ===================="
    echo "NWChem executable created at: $NWCHEM_TOP/bin/LINUX64/nwchem"
    ls -la $NWCHEM_TOP/bin/LINUX64/nwchem
else
    echo "==================== NWChem build FAILED ===================="
    echo "Check build.log for errors"
    echo "Last 50 lines of build log:"
    tail -50 build.log
fi

echo "==================== Build process finished ===================="