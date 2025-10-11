#!/bin/bash
#PBS -N intel_mpi
#PBS -j oe
#PBS -q normalsr
#PBS -P il65
#PBS -l ncpus=416
#PBS -l other=hyperthread
#PBS -l mem=500gb
#PBS -l jobfs=1gb
#PBS -l walltime=00:01:00
#PBS -l wd
#PBS -l storage=scratch/il65

cd $PBS_O_WORKDIR

curr=/scratch/il65/shared_project_folder/NEWSHAREDWORKSPACE/INTEL/intelmpi_llvm_ofast

module purge
module load intel-compiler-llvm/2025.2.0
module load intel-mkl/2025.2.0
module load ucx
module load intel-vtune/2025.0.1
module load intel-mpi/2021.16.0

export MKLROOT=/apps/intel-tools/intel-mkl/2025.2.0
export LD_LIBRARY_PATH=$MKLROOT/lib/intel64:$I_MPI_ROOT/lib:$LD_LIBRARY_PATH
export LD_PRELOAD=$MKLROOT/lib/intel64/libmkl_core.so # handling _dl_init things

# UCX / MPI settings for multi-node
# Intel MPI + UCX
export I_MPI_FABRICS=shm:ofi        # shared memory for intra-node, OFI (UCX) for inter-node
export I_MPI_OFI_PROVIDER=mlx       # Mellanox mlx5 IB
export I_MPI_PIN=1                   # enable pinning of ranks
export I_MPI_PIN_DOMAIN=core        # pin each rank to a core
export I_MPI_PIN_ORDER=compact      # compact rank ordering
export I_MPI_ADJUST_REDUCE=1        # optimize collectives
export I_MPI_DEBUG=0                # debug off for production


# UCX tuning (Intel MPI uses UCX via OFI)
export UCX_TLS=rc_x,dc_x,ud,self,sm       # transports: RC, DC, UD, self, shared memory
export UCX_NET_DEVICES=mlx5_0:1           # network device
export UCX_MEMTYPE_CACHE=n
export UCX_RNDV_SCHEME=get_zcopy          # RDMA rendezvous
export UCX_MAX_EAGER_RAILS=1
export UCX_RNDV_THRESH=16384
export UCX_IB_SL=5
export UCX_RC_TX_QUEUE_LEN=256
export UCX_RC_RX_QUEUE_LEN=512
export UCX_IB_NUM_PATHS=2
export UCX_LOG_LEVEL=error



APP=${curr}/nwchem/bin/LINUX64/nwchem
INPUT=${curr}/noguess.nw
OUTPUT=./out.nwout

# OpenMP threads per MPI process
export OMP_NUM_THREADS=1        # Adjust to match physical cores per process
export MKL_NUM_THREADS=1

# Memory allocation settings
export HUGETLB_MORECORE=yes
export MALLOC_HUGEPAGES=1
export MALLOC_HUGE_2MB_MAX=100G

# NUMA & MPI binding policies


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

export ARMCI_VERBOSE=0
export GA_DEBUG=0

export ARMCI_DEFAULT_SHMMAX=45056
export ARMCI_NETWORK=ARMCI-MPI

# so i don't loose this
# -gtool "vtune -collect memory-access -r vtunemem" \
# -genv VTUNE_RANK 0 \

mpirun -np $TOTAL_RANKS \
        -ppn $RANKS_PER_NODE \
        -genv OMP_NUM_THREADS $OMP_NUM_THREADS \
        -genv OMP_PLACES cores \
        -genv OMP_PROC_BIND close \
        $APP $INPUT > $OUTPUT