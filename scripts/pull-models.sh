#!/usr/bin/env bash
set -Eeuo pipefail

# Defaults are chosen for an RTX 5070 Ti with 16GB VRAM and only 16GB system RAM.
# FULL=1 also downloads the 14GB gpt-oss model.
FULL="${FULL:-0}"

WINDOWS_HOST_IP="$(ip route show default | awk '{print $3; exit}')"
OLLAMA_URL="${OLLAMA_BASE_URL:-http://${WINDOWS_HOST_IP}:11434}"

pull_model() {
  local model="$1"
  echo "==> Pulling ${model}"
  curl --fail --no-buffer --show-error \
    "${OLLAMA_URL}/api/pull" \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"${model}\"}"
  echo
}

curl -fsS "${OLLAMA_URL}/api/tags" >/dev/null || {
  echo "Ollama is not reachable at ${OLLAMA_URL}. Launch Ollama on Windows first." >&2
  exit 1
}

pull_model "qwen3.5:9b"
pull_model "gemma4:12b"

if [[ "$FULL" == "1" ]]; then
  pull_model "gpt-oss:20b"
else
  echo "Skipping gpt-oss:20b. Run FULL=1 ./pull-models.sh after upgrading system RAM or when you are ready to test it."
fi

echo "Installed models:"
curl -fsS "${OLLAMA_URL}/api/tags" | jq -r '.models[] | "- \(.name) (\(.size / 1073741824 | floor) GiB)"'
