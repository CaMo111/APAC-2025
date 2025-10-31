#!/bin/bash
#SBATCH -p hpcai
#SBATCH -N 1
#SBATCH --ntasks-per-node=1
#SBATCH --gpus-per-node=nvidia_h200:8
#SBATCH --exclusive
#SBATCH -t 00:05:00
#SBATCH -o slurm-%j.out
#SBATCH -e slurm-%j.err
#SBATCH --hint=multithread

set -euo pipefail

export NCCL_DEBUG=WARN
export DIST_INIT_ADDR="$(scontrol show hostnames "$SLURM_JOB_NODELIST" | head -n 1)"
echo "DIST_INIT_ADDR=${DIST_INIT_ADDR}"

export IMAGE="$HOME/sglang_v0.5.3rc1-cu126.sif"

# Hopper
export TORCH_CUDA_ARCH_LIST="9.0"

# pass-through to container
export SINGULARITYENV_NCCL_DEBUG="$NCCL_DEBUG"
export SINGULARITYENV_DIST_INIT_ADDR="$DIST_INIT_ADDR"
export SINGULARITYENV_TORCH_CUDA_ARCH_LIST="$TORCH_CUDA_ARCH_LIST"

time srun --label --cpu-bind=socket \
  --nodes="$SLURM_JOB_NUM_NODES" --ntasks-per-node=1 \
  bash -lc '
    set -euo pipefail
    ulimit -l unlimited || true

    # Clean any stale FlashInfer cache (fixes corrupted .so)
    rm -rf "$HOME/.cache/flashinfer/"* || true

    # Per-rank Triton cache on local node tmp
    CACHE_ROOT="${SLURM_TMPDIR:-${TMPDIR:-/tmp}}/triton/${SLURM_JOB_ID}/node${SLURM_NODEID}"
    export TRITON_CACHE_DIR="${CACHE_ROOT}/rank${SLURM_PROCID:-0}"
    mkdir -p "$TRITON_CACHE_DIR"
    echo "TRITON_CACHE_DIR=$TRITON_CACHE_DIR"

    # Torch profiler dir (optional)
    export SGLANG_TORCH_PROFILER_DIR="$HOME/sgprofile/node${SLURM_NODEID}"
    mkdir -p "$SGLANG_TORCH_PROFILER_DIR"
    echo "profile dir: $SGLANG_TORCH_PROFILER_DIR"

    # Flashinfer per rank storing
    export FLASHINFER_JIT_DIR="$CACHE_ROOT/flashinfer"
    export XDG_CACHE_HOME="$CACHE_ROOT/xdg"      # in case FlashInfer falls back to XDG
    mkdir -p "$FLASHINFER_JIT_DIR" "$XDG_CACHE_HOME"
    export SINGULARITYENV_FLASHINFER_JIT_DIR="$FLASHINFER_JIT_DIR"
    export SINGULARITYENV_XDG_CACHE_HOME="$XDG_CACHE_HOME"

    mkdir -p "$CACHE_ROOT/torch_ext"


    BIND_CACHE="--bind $CACHE_ROOT/flashinfer:$HOME/.cache/flashinfer \
                --bind $CACHE_ROOT/torch_ext:$HOME/.cache/torch/extensions"

    # Pass into container
    export SINGULARITYENV_TRITON_CACHE_DIR="$TRITON_CACHE_DIR"
    export SINGULARITYENV_SGLANG_TORCH_PROFILER_DIR="$SGLANG_TORCH_PROFILER_DIR"
    export SINGULARITYENV_SLURM_NODEID="$SLURM_NODEID"
    export SINGULARITYENV_SLURM_PROCID="$SLURM_PROCID"
    export SINGULARITYENV_SLURM_JOB_ID="$SLURM_JOB_ID"
    export SINGULARITYENV_SLURM_JOB_NUM_NODES="$SLURM_JOB_NUM_NODES"
    export SINGULARITYENV_IMAGE="$IMAGE"

    export NCCL_NET_GDR_LEVEL=5

    # Run inside the container
    singularity exec --nv $BIND_CACHE $IMAGE bash -lc "
      set -euo pipefail
      python3 -m sglang.bench_offline_throughput \
        --model-path deepseek-ai/DeepSeek-R1 \
        --dataset-path \$HOME/ShareGPT_V3_unfiltered_cleaned_split.json \
        --num-prompts 2000 --load-format dummy --seed 2025 --dtype bfloat16 \
        --tp 4 --dp 4 --pp 2 --enable-torch-compile --enable-dp-attention --nnodes \$SLURM_JOB_NUM_NODES --trust-remote-code \
        --dist-init-addr \$DIST_INIT_ADDR:5000 --node-rank \$SLURM_NODEID
    "
  '

