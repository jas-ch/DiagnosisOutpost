#!/usr/bin/env bash
# Train all on-device classifier groups from processed datasets.
#
# Convenience wrapper around train_image_classifier.py and train_audio_classifier.py.
# Runs each task with its corresponding config from training/configs/.
#
# Usage:
#   cd models
#   ./training/train_all.sh
#   ./training/train_all.sh --task rash
#   ./training/train_all.sh --task cough --epochs 20 --batch-size 16
#   ./training/train_all.sh --weights none
#   ./training/train_all.sh --skip-weights-cache

set -euo pipefail

TASK="all"
EPOCHS=""
BATCH_SIZE=""
WEIGHTS="imagenet"
SKIP_WEIGHTS_CACHE=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${MODELS_DIR}"

# Workaround for Blackwell GPUs (sm_120): make sure TensorFlow loads the
# newer libnvJitLink from the venv instead of the older system copy.
# Without this, TF can fail with CUDA_ERROR_INVALID_PTX / symbol lookup errors.
NVJITLINK_DIR="${MODELS_DIR}/.venv/lib/python3.12/site-packages/nvidia/nvjitlink/lib"
if [[ -d "${NVJITLINK_DIR}" ]]; then
  export LD_LIBRARY_PATH="${NVJITLINK_DIR}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)
      TASK="$2"
      shift 2
      ;;
    --epochs)
      EPOCHS="$2"
      shift 2
      ;;
    --batch-size)
      BATCH_SIZE="$2"
      shift 2
      ;;
    --weights)
      WEIGHTS="$2"
      shift 2
      ;;
    --skip-weights-cache)
      SKIP_WEIGHTS_CACHE=1
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--task TASK] [--epochs N] [--batch-size N] [--weights W] [--skip-weights-cache]"
      echo "  TASK:               one of rash, tongue, wound, face, cough, all (default: all)"
      echo "  EPOCHS:             override epochs from the config"
      echo "  BATCH_SIZE:         override batch size"
      echo "  WEIGHTS:            imagenet, none, or path to local weights file (default: imagenet)"
      echo "  --skip-weights-cache: skip the ImageNet weight pre-cache step"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Run '$0 --help' for usage."
      exit 1
      ;;
  esac
done

EXTRA_ARGS=()
if [[ -n "${EPOCHS}" ]]; then
  EXTRA_ARGS+=(--epochs "${EPOCHS}")
fi
if [[ -n "${BATCH_SIZE}" ]]; then
  EXTRA_ARGS+=(--batch-size "${BATCH_SIZE}")
fi

declare -A IMAGE_CONFIGS=(
  [rash]="training/configs/rash_mobilenetv2.yaml"
  [tongue]="training/configs/tongue_mobilenetv2.yaml"
  [wound]="training/configs/wound_mobilenetv2.yaml"
  [face]="training/configs/face_mobilenetv2.yaml"
)

declare -A AUDIO_CONFIGS=(
  [cough]="training/configs/cough_audio_cnn.yaml"
)

cache_imagenet_weights() {
  echo "============================================================"
  echo "Pre-caching ImageNet MobileNetV2 weights (one-time download)"
  echo "============================================================"
  python - <<'PY'
import sys
import tensorflow as tf
try:
    tf.keras.applications.MobileNetV2(weights='imagenet', include_top=False)
    print("ImageNet weights cached successfully.")
except Exception as exc:
    print(f"ERROR: Could not cache ImageNet weights: {exc}", file=sys.stderr)
    sys.exit(1)
PY
}

# Cache ImageNet weights once before image training if requested.
if [[ "${WEIGHTS}" == "imagenet" && "${SKIP_WEIGHTS_CACHE}" -ne 1 ]]; then
  cache_imagenet_weights
fi

run_image_task() {
  local task="$1"
  local config="${IMAGE_CONFIGS[${task}]}"
  echo "============================================================"
  echo "Training image classifier: ${task}"
  echo "  config: ${config}"
  echo "  weights: ${WEIGHTS}"
  echo "============================================================"
  python training/train_image_classifier.py --config "${config}" --weights "${WEIGHTS}" "${EXTRA_ARGS[@]}"
}

run_audio_task() {
  local task="$1"
  local config="${AUDIO_CONFIGS[${task}]}"
  echo "============================================================"
  echo "Training audio classifier: ${task}"
  echo "  config: ${config}"
  echo "============================================================"
  python training/train_audio_classifier.py --config "${config}" "${EXTRA_ARGS[@]}"
}

if [[ "${TASK}" == "all" ]]; then
  for task in rash tongue wound face cough; do
    if [[ -n "${IMAGE_CONFIGS[${task}]:-}" ]]; then
      run_image_task "${task}"
    else
      run_audio_task "${task}"
    fi
  done
elif [[ -n "${IMAGE_CONFIGS[${TASK}]:-}" ]]; then
  run_image_task "${TASK}"
elif [[ -n "${AUDIO_CONFIGS[${TASK}]:-}" ]]; then
  run_audio_task "${TASK}"
else
  echo "Unknown task: ${TASK}"
  echo "Supported tasks: rash, tongue, wound, face, cough, all"
  exit 1
fi

echo "============================================================"
echo "All requested classifier training runs complete."
echo "Exported artifacts are in models/exported/"
echo "============================================================"
