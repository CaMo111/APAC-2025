#!/bin/bash
#SBATCH -p hpcai
#SBATCH -N 2
#SBATCH --ntasks-per-node=1
#SBATCH --gpus-per-node=nvidia_h200:8
#SBATCH --exclusive
#SBATCH -t 00:45:00
#SBATCH -o slurm-%j.out
#SBATCH -e slurm-%j.err
#SBATCH --hint=multithread

set -euo pipefail

# ---------- basic env ----------
export NCCL_DEBUG=WARN
export DIST_INIT_ADDR="$(scontrol show hostnames "$SLURM_JOB_NODELIST" | head -n 1)"
echo "DIST_INIT_ADDR=${DIST_INIT_ADDR}"

# Hopper
export TORCH_CUDA_ARCH_LIST="9.0"

# Pass-through to container
export SINGULARITYENV_NCCL_DEBUG="$NCCL_DEBUG"
export SINGULARITYENV_DIST_INIT_ADDR="$DIST_INIT_ADDR"
export SINGULARITYENV_TORCH_CUDA_ARCH_LIST="$TORCH_CUDA_ARCH_LIST"

# ---------- image & knobs ----------
IMAGE="${IMAGE:-$HOME/sglang_v0.5.3rc1-cu126.sif}"

MODEL="${MODEL:-deepseek-ai/DeepSeek-R1}"
DTYPE="${DTYPE:-bfloat16}"
TP="${TP:-4}"
DP="${TP:-4}"
PP="${TP:-2}"

SERVER_PORT="${SERVER_PORT:-30000}"
ROUTER_PORT="${ROUTER_PORT:-31000}"
ROUTER_POLICY="${ROUTER_POLICY:-cache_aware}"

# ---------- resolve nodes ----------
readarray -t NODES < <(scontrol show hostnames "$SLURM_NODELIST")
NODE0="${NODES[0]}"
NODE1="${NODES[1]}"
echo "NODE0=$NODE0 NODE1=$NODE1"

# ---------- helpers ----------
wait_ready() {
	local url="$1" tries="${2:-180}"
	until curl -fsS "$url" >/dev/null 2>&1; do
		((tries--)) || {
			echo "Timeout waiting for $url"
			return 1
		}
		sleep 2
	done
}

# ---------- launch servers (one per node) ----------
# Note: --overlap so we can start the router later on node0 within the same allocation.
srun -N 2 -n 2 -w "$NODE0","$NODE1" --label --overlap --cpu-bind=none \
	--ntasks-per-node=1 \
	bash -lc '
    set -euo pipefail
    ulimit -l unlimited || true

    # Clean any stale FlashInfer cache (fixes corrupted .so)
    rm -rf "$HOME/.cache/flashinfer/"* || true

    # Per-node cache roots
    CACHE_ROOT="${SLURM_TMPDIR:-${TMPDIR:-/tmp}}/triton/${SLURM_JOB_ID}/node${SLURM_NODEID}"
    export TRITON_CACHE_DIR="${CACHE_ROOT}/rank${SLURM_PROCID:-0}"
    mkdir -p "$TRITON_CACHE_DIR"
    echo "TRITON_CACHE_DIR=$TRITON_CACHE_DIR"

    export SGLANG_TORCH_PROFILER_DIR="$HOME/sgprofile/node${SLURM_NODEID}"
    mkdir -p "$SGLANG_TORCH_PROFILER_DIR"

    export FLASHINFER_JIT_DIR="$CACHE_ROOT/flashinfer"
    export XDG_CACHE_HOME="$CACHE_ROOT/xdg"
    mkdir -p "$FLASHINFER_JIT_DIR" "$XDG_CACHE_HOME"

    mkdir -p "$CACHE_ROOT/torch_ext"

    BIND_CACHE="--bind $CACHE_ROOT/flashinfer:$HOME/.cache/flashinfer \
                --bind $CACHE_ROOT/torch_ext:$HOME/.cache/torch/extensions"

    # Pass into container
    export SINGULARITYENV_TRITON_CACHE_DIR="$TRITON_CACHE_DIR"
    export SINGULARITYENV_SGLANG_TORCH_PROFILER_DIR="$SGLANG_TORCH_PROFILER_DIR"
    export SINGULARITYENV_FLASHINFER_JIT_DIR="$FLASHINFER_JIT_DIR"
    export SINGULARITYENV_XDG_CACHE_HOME="$XDG_CACHE_HOME"
    export SINGULARITYENV_SLURM_NODEID="$SLURM_NODEID"
    export SINGULARITYENV_SLURM_PROCID="$SLURM_PROCID"
    export SINGULARITYENV_SLURM_JOB_ID="$SLURM_JOB_ID"
    export SINGULARITYENV_SLURM_JOB_NUM_NODES="$SLURM_JOB_NUM_NODES"

    singularity exec --nv $BIND_CACHE '"$IMAGE"' bash -lc "
      set -euo pipefail
      python3 -m sglang.launch_server \
        --model-path '"$MODEL"' \
        --dtype '"$DTYPE"' \
        --tp '"$TP"' \
        --pp '"$PP"' \
        --dp '"$DP"' \
        --enable-dp-attention \
        --host 0.0.0.0 \
        --port '"$SERVER_PORT"' \
        --trust-remote-code \
        --load-format dummy
    "
  ' &

# ---------- wait for servers to be healthy ----------
echo "Waiting for servers to be ready..."
wait_ready "http://$NODE0:$SERVER_PORT/health"
wait_ready "http://$NODE1:$SERVER_PORT/health"
echo "Servers healthy."

# ---------- start router on NODE0 (foreground) ----------
# Requires the 'sglang-router' package inside your image.
echo "Starting router on $NODE0 (port $ROUTER_PORT)..."
srun -N 1 -n 1 -w "$NODE0" --overlap --cpu-bind=none \
	bash -lc "
    singularity exec --nv $IMAGE python3 -m sglang_router.launch_router \
      --worker-urls http://$NODE0:$SERVER_PORT http://$NODE1:$SERVER_PORT \
      --host 0.0.0.0 \
      --port $ROUTER_PORT \
      --policy $ROUTER_POLICY
  "
