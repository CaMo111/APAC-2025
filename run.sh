#!/bin/bash
#PBS -N intel_mpimpt
#PBS -j oe
#PBS -q normalsr
#PBS -P il65
#PBS -l ncpus=416
#PBS -l mem=500gb
#PBS -l jobfs=1gb
#PBS -l walltime=00:15:00
#PBS -l wd
#PBS -l storage=scratch/il65

cd $PBS_O_WORKDIR

curr=/scratch/il65/shared_project_folder/NEWSHAREDWORKSPACE/INTEL/PUREMPIBUILD_ofastoptimised_mpipr

module purge
module load intel-compiler-llvm/2025.2.0
module load openmpi/5.0.8
module load intel-mkl/2025.2.0
module load ucx
module load intel-vtune/2025.0.1

# UCX / MPI settings for multi-node
export OMPI_MCA_pml=ucx
export OMPI_MCA_osc=ucx
export UCX_TLS=rc,dc,self,sm
export UCX_NET_DEVICES=mlx5_0:1
export UCX_MEMTYPE_CACHE=n
export UCX_LOG_LEVEL=warn
export UCX_WARN_UNUSED_ENV_VARS=n

export OMPI_MCA_mpi_leave_pinned=1
export OMPI_MCA_mpi_leave_pinned_pipeline=0
export OMPI_MCA_mtl=^psm,psm2

# Optional UCX tuning
export UCX_RNDV_SCHEME=get_zcopy
export UCX_MAX_EAGER_RAILS=1

APP=${curr}/nwchem
INPUT=${curr}/giac.nw
OUTPUT=${curr}/run.nwout

# OpenMP threads per MPI process
export OMP_NUM_THREADS=2        # Adjust to match physical cores per process
export MKL_NUM_THREADS=2

# Memory allocation settings
export HUGETLB_MORECORE=yes
export MALLOC_HUGEPAGES=1
export MALLOC_HUGE_2MB_MAX=100G

# NUMA & MPI binding policies
export OMPI_MCA_hwloc_base_binding_policy=core
export OMPI_MCA_rmaps_base_mapping_policy=PE=2:OVERSUBSCRIBE  # PE=OMP_NUM_THREADS per MPI rank

# Network tuning
export OMPI_MCA_coll_hcoll_enable=1
export UCX_IB_GPU_DIRECT_RDMA=no

# Check allocation and force 4-node distribution
echo "=== RESOURCE ALLOCATION CHECK ==="
NNODES=$(cat $PBS_NODEFILE | sort | uniq | wc -l)
echo "Number of nodes allocated: $NNODES"

if [ $NNODES -ne 4 ]; then
    echo "ERROR: Expected 4 nodes, got $NNODES nodes!"
    cat $PBS_NODEFILE | sort | uniq
    exit 1
fi

echo "Nodes allocated:"
cat $PBS_NODEFILE | sort | uniq
echo "Total CPU slots available:"
cat $PBS_NODEFILE | wc -l
echo "================================="
echo ""

# Total MPI ranks = ncpus / OMP_NUM_THREADS
TOTAL_RANKS=$((416 / OMP_NUM_THREADS))
RANKS_PER_NODE=$((TOTAL_RANKS / NNODES))

echo "Launching $TOTAL_RANKS MPI ranks, $OMP_NUM_THREADS threads each (~$RANKS_PER_NODE ranks per node)"

mpirun -np $TOTAL_RANKS \
       --map-by ppr:$RANKS_PER_NODE:node:PE=$OMP_NUM_THREADS \
       --bind-to core \
       --report-bindings \
       $APP $INPUT > $OUTPUT