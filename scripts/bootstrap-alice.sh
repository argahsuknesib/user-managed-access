#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./lib/uma.sh
source "${SCRIPT_DIR}/lib/uma.sh"

BASE_URL="${BASE_URL:-http://localhost:3000}"
UMA_URL="${UMA_URL:-http://localhost:4000}"
DERIVED_META_URL="${BASE_URL}/alice/.meta"
PATCH_FILE="${ROOT_DIR}/packages/css/config/derived-alice.patch.sparql"

ensure_container() {
  local container_url="$1"

  if uma_get "${container_url}" >/dev/null 2>&1; then
    return 0
  fi

  uma_put_empty "${container_url}"
}

verify_metadata() {
  local meta_output

  meta_output="$(uma_get "${DERIVED_META_URL}")"

  grep -F '<urn:npm:solid:derived-resources:template> "latest"' <<<"${meta_output}" >/dev/null
  grep -F '<urn:npm:solid:derived-resources:selector> "http://localhost:3000/alice/spo2/*"' <<<"${meta_output}" >/dev/null
  grep -F '<urn:npm:solid:derived-resources:template> "latest-anomaly"' <<<"${meta_output}" >/dev/null
  grep -F '<urn:npm:solid:derived-resources:selector> "http://localhost:3000/alice/derived/anomaly-alert/*"' \
    <<<"${meta_output}" >/dev/null

  printf '%s\n' "${meta_output}"
}

main() {
  wait_for_url "${UMA_URL}/uma/keys" 120
  wait_for_url "${BASE_URL}/" 120

  ensure_container "${BASE_URL}/alice/spo2/"
  ensure_container "${BASE_URL}/alice/derived/"
  ensure_container "${BASE_URL}/alice/derived/anomaly-alert/"
  uma_patch "${DERIVED_META_URL}" "${PATCH_FILE}"

  local meta_output
  meta_output="$(verify_metadata)"

  if [ "$(grep -F -c 'latest-anomaly' <<<"${meta_output}")" -gt 1 ] || \
    [ "$(grep -F -c '"http://localhost:3000/alice/derived/anomaly-alert/*"' <<<"${meta_output}")" -gt 1 ]; then
    printf '%s\n' \
      "Warning: legacy duplicate derived configs are still present in ${DERIVED_META_URL}." \
      "The bootstrap no longer inserts new duplicate configs, but existing blank-node duplicates cannot be cleaned" \
      "safely with CSS's supported PATCH forms because their generated identifiers are not addressable." >&2
  fi

  cat <<EOF
Bootstrap complete. Resources verified:
 - ${BASE_URL}/alice/spo2/
 - ${BASE_URL}/alice/derived/
 - ${BASE_URL}/alice/derived/anomaly-alert/
 - ${DERIVED_META_URL}
EOF
}

main "$@"
