#!/bin/bash
#PBS -N nwchem_install_intel_llvm
#PBS -q copyq
#PBS -l jobFS=10GB
#PBS -l ncpus=1
#PBS -l mem=32gb
#PBS -l walltime=04:00:00
#PBS -j oe
#PBS -o build.log

path=/scratch/il65/shared_project_folder/NEWSHAREDWORKSPACE/INTEL/intelmpi_llvm_ofast

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
echo "Modules loaded:"
module list

# ============================================
# Compiler settings (LLVM ICX) - FIXED
# ============================================
export FC=ifx
export CC=icx
export CXX=icpx
export OMPI_FC=mpiifort #$FC
export OMPI_CC=mpiicc #$CC
export OMPI_CXX=mpiicpc #$CXX

#export FCFLAGS="-Ofast -xHost -fp-model fast=2 -fPIC -ipo -qopenmp -i8 -fallow-argument-mismatch"
#export CCFLAGS="-Ofast -xHost -fp-model fast=2 -fPIC -ipo"
#export CXXFLAGS="-Ofast -xHost -fp-model fast=2 -fPIC -ipo"
export FCFLAGS="-Ofast -march=sapphirerapids -fp-model fast=2 -fopenmp -i8 -fPIC -ipo -fallow-argument-mismatch -fno-operator-overloading-check"
export CCFLAGS="-Ofast -march=sapphirerapids -fp-model fast=2 -fPIC -ipo"
export CXXFLAGS="-Ofast -march=sapphirerapids -fp-model fast=2 -fPIC -ipo"

echo "FC=$FC, CC=$CC, CXX=$CXX"
echo "FCFLAGS=$FCFLAGS"
echo "CCFLAGS=$CCFLAGS"
echo "CXXFLAGS=$CXXFLAGS"

# ============================================
# NWChem build options - FIXED
# ============================================
export USE_MPI=y
export USE_OPENMP=y
export USE_GA=y

export NWCHEM_TARGET=LINUX64

# Start with basic modules first, can expand later
export NWCHEM_MODULES="all"
export BLAS_SIZE=8
export SCALAPACK_SIZE=8

# ============================================
# MKL BLAS/LAPACK settings - FIXED
# ============================================
# Use proper MKL linking with dynamic libraries for better compatibility
# Threaded MKL ILP64 (Intel MPI version)
export BLASOPT="-L${MKLROOT}/lib/intel64 -Wl,--start-group \
        -lmkl_intel_ilp64 -lmkl_core -lmkl_intel_thread -Wl,--end-group \
        -liomp5 -lpthread -lm -ldl"

export BLAS_LIB="$BLASOPT"
export LAPACK_LIB="$BLASOPT"

# ScaLAPACK for Intel MPI
export USE_SCALAPACK=y
export SCALAPACK_LIB="-L${MKLROOT}/lib/intel64 \
        -lmkl_scalapack_ilp64 -lmkl_blacs_intelmpi_ilp64 ${BLASOPT}"


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

#export EXTERNAL_GA_PATH=/scratch/il65/shared_project_folder/NEWSHAREDWORKSPACE/GLOBALARRAY/ga-install
#export GA_DIR=${EXTERNAL_GA_PATH}
#export GA_LIB="${EXTERNAL_GA_PATH}/lib"
#export GA_INC="${EXTERNAL_GA_PATH}/include"

# Add GA library paths to linker and compiler
#export LDFLAGS="-L${GA_LIB} ${LDFLAGS}"
#export CPPFLAGS="-I${GA_INC} ${CPPFLAGS}"
#export LIBRARY_PATH="${GA_LIB}:${LIBRARY_PATH}"

#echo "GA paths configured:"
#echo "GA_DIR: $GA_DIR"
#echo "GA_LIB: $GA_LIB"
#echo "GA_INC: $GA_INC"

# ============================================
# Build NWChem - IMPROVED
# ============================================
cd $NWCHEM_TOP/src
#echo "Cleaning previous build..."

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