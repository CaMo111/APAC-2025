#!/bin/bash

# Load compiler modules
echo "Loading modules..."
module purge
module load intel-compiler-llvm/2025.2.0
module load openmpi/5.0.8
module load intel-mkl/2025.2.0
echo "Modules loaded:"
module list

git clone https://github.com/GlobalArrays/ga.git
curr=/scratch/il65/shared_project_folder/NEWSHAREDWORKSPACE/GLOBALARRAY

GA_SRC=ga
GA_INSTALL=${curr}/ga-install

cd $GA_SRC


GA_INSTALL=${curr}/ga-install
cd $GA_SRC

export INTEL_LICENSE_FILE=/apps/intel-tools/intel-compiler-llvm/2025.2.0/licensing
export MKLROOT=/apps/intel-tools/intel-mkl/2025.2.0
export LD_LIBRARY_PATH=${MKLROOT}/lib/intel64:${LD_LIBRARY_PATH}

./autogen.sh

# ILP64 (8-byte integer) settings
export BLASOPT="-L${MKLROOT}/lib/intel64 -Wl,--start-group -lmkl_intel_ilp64 -lmkl_core -lmkl_intel_thread -Wl,--end-group -liomp5 -lpthread -lm -ldl"
export SCALAPACK_LIB="-L${MKLROOT}/lib/intel64 -lmkl_scalapack_ilp64 -lmkl_blacs_openmpi_ilp64 ${BLASOPT}"

# Critical: Set flags for 8-byte integers
export FFLAGS="-i8"
export FCFLAGS="-i8"
export F77_INT_FLAG="-i8"
export CFLAGS="-DMKL_ILP64"
export CPPFLAGS="-DMKL_ILP64"


./configure --prefix=$GA_INSTALL \
            --with-blas8="$BLASOPT" \
            --with-lapack8="$BLASOPT" \
            --with-scalapack8="$SCALAPACK_LIB" \
            --enable-i8 \
            --with-mpi-pr \
            MPICC=mpicc MPICXX=mpicxx MPIF77=mpif77 \
            FFLAGS="$FFLAGS" FCFLAGS="$FCFLAGS" \
            CFLAGS="$CFLAGS" CPPFLAGS="$CPPFLAGS"

make -j30
make install

# Point NWChem to the installed GA
export EXTERNAL_GA_PATH=$GA_INSTALL