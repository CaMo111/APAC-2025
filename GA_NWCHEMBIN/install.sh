#!/bin/bash
#PBS -N nwchem_install_intel_llvm
#PBS -q copyq
#PBS -l jobFS=10GB
#PBS -l ncpus=1
#PBS -l mem=32gb
#PBS -l walltime=04:00:00
#PBS -j oe
#PBS -o build.log

echo "==================== Starting NWChem build ===================="

# ============================================
# Paths
# ============================================
#path=/scratch/il65/shared_project_folder/NEWSHAREDWORKSPACE/INTEL/intelllvm_armciMT #/home/565/nc1144/nwchem_optimise/nathanCulshaw/INTEL_NWCHEM/intel_llvm_3sep_o3fastflags/intel_llvm_3sep_o3fastflags
path=/scratch/il65/shared_project_folder/NEWSHAREDWORKSPACE/INTEL/GA

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
module load openmpi/5.0.8
module load intel-mkl/2025.2.0
echo "Modules loaded:"
module list

# ============================================
# Compiler settings (LLVM ICX) - FIXED
# ============================================
export FC=ifx
export CC=icx
export CXX=icpx
export OMPI_FC=$FC
export OMPI_CC=$CC
export OMPI_CXX=$CXX

export FCFLAGS="-Ofast -xHost -fp-model fast=2 -fPIC -ipo -qopenmp -i8 -fallow-argument-mismatch"
export CCFLAGS="-Ofast -xHost -fp-model fast=2 -fPIC -ipo"
export CXXFLAGS="-Ofast -xHost -fp-model fast=2 -fPIC -ipo"

#export FCFLAGS="-O3 -xHost -fp-model fast=2 -fPIC -i8 -fallow-argument-mismatch"
#export CCFLAGS="-O3 -xHost -fp-model fast=2 -fPIC"
#export CXXFLAGS="-O3 -xHost -fp-model fast=2 -fPIC"

echo "Compiler settings:"
echo "FC=$FC, CC=$CC, CXX=$CXX"
echo "FCFLAGS=$FCFLAGS"
echo "CCFLAGS=$CCFLAGS"
echo "CXXFLAGS=$CXXFLAGS"

# ============================================
# NWChem build options - FIXED
# ============================================
export USE_MPI=y
export USE_OPENMP=y

# Build GA (Global Arrays) first
# ============================================
export USE_GA=y

#cd $NWCHEM_TOP/src/tools/ga-5.9.2
#export EXTERNAL_GA_PATH=$NWCHEM_TOP

export NWCHEM_TARGET=LINUX64

# Start with basic modules first, can expand later
export NWCHEM_MODULES="all"

export BLAS_SIZE=8
export SCALAPACK_SIZE=8

# ============================================
# MKL BLAS/LAPACK settings - FIXED
# ============================================
# Use proper MKL linking with dynamic libraries for better compatibility

# BLAS/LAPACK (threaded MKL, ILP64)
export BLASOPT="-L${MKLROOT}/lib/intel64 -Wl,--start-group \
-lmkl_intel_ilp64 -lmkl_core -lmkl_intel_thread -Wl,--end-group \
-liomp5 -lpthread -lm -ldl"

# Tell NWChem explicitly
export BLAS_LIB="$BLASOPT"
export LAPACK_LIB="$BLASOPT"

# ScaLAPACK (threaded, OpenMPI + MKL)
export USE_SCALAPACK=y
export SCALAPACK_LIB="-L${MKLROOT}/lib/intel64 \
-lmkl_scalapack_ilp64 -lmkl_blacs_openmpi_ilp64 ${BLASOPT}"

echo "BLASOPT=$BLASOPT"
echo "SCALAPACK_LIB=$SCALAPACK_LIB"

# ============================================
# ARMCI / MPI settings - FIXED
# ============================================
export ARMCI_NETWORK=MPI-PR
export EXTERNAL_ARMCI_PATH=$NWCHEM_TOP/external-armci

# Fetch NWChem tools first
cd $NWCHEM_TOP/src/tools

echo "Fetching NWChem tools..."
./get-tools-github

echo "Installing ARMCI-MPI..."
./install-armci-mpi

# ============================================
# Additional environment variables for Intel compilers
# ============================================
export INTEL_LICENSE_FILE=/apps/intel-tools/intel-compiler-llvm/2025.2.0/licensing
export LD_LIBRARY_PATH=${MKLROOT}/lib/intel64:${LD_LIBRARY_PATH}

# Point NWChem to the installed GA
export EXTERNAL_GA_PATH=/scratch/il65/shared_project_folder/NEWSHAREDWORKSPACE/GLOBALARRAY/ga-install #$GA_INSTALL

# ============================================
# Build NWChem - IMPROVED
# ============================================
cd $NWCHEM_TOP/src
#echo "Cleaning previous build..."
#make clean

echo "Generating NWChem configuration..."
make nwchem_config

echo "Configuration check:"
echo "NWCHEM_TARGET: $NWCHEM_TARGET"
echo "NWCHEM_MODULES: $NWCHEM_MODULES"
echo "FC: $FC"
echo "CC: $CC"

echo "Starting compilation with reduced parallelism for stability..."
# Use fewer parallel jobs to reduce memory pressure and compilation errors
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