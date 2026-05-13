#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./lib/uma.sh
source "${SCRIPT_DIR}/lib/uma.sh"

BASE_URL="${BASE_URL:-http://localhost:3000}"
UMA_URL="${UMA_URL:-http://localhost:4000}"

# Wait for services
wait_for_url "${UMA_URL}/uma/keys" 120
wait_for_url "${BASE_URL}/" 120

# Create the base alice containers and derived metadata
# This is the standard bootstrap for alice derived resources
ensure_container() {
  local container_url="$1"

  if uma_get "${container_url}" >/dev/null 2>&1; then
    return 0
  fi

  uma_put_empty "${container_url}"
}

# Ensure all required containers exist
ensure_container "${BASE_URL}/alice/spo2/"
ensure_container "${BASE_URL}/alice/derived/"
ensure_container "${BASE_URL}/alice/derived/anomaly-alert/"

# Patch metadata for derived resources
PATCH_FILE="${ROOT_DIR}/packages/css/config/derived-alice.patch.sparql"
if [ -f "${PATCH_FILE}" ]; then
  uma_patch "${BASE_URL}/alice/.meta" "${PATCH_FILE}"
fi

echo "Setup complete: Alice derived resources configured"
