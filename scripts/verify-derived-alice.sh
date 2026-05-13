#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./lib/uma.sh
source "${SCRIPT_DIR}/lib/uma.sh"

BASE_URL="${BASE_URL:-http://localhost:3000}"
UMA_URL="${UMA_URL:-http://localhost:4000}"
DERIVED_META_URL="${BASE_URL}/alice/.meta"
ALERT_CONTAINER_URL="${BASE_URL}/alice/derived/anomaly-alert/"
LATEST_ANOMALY_URL="${BASE_URL}/alice/derived/latest-anomaly"

main() {
  wait_for_url "${UMA_URL}/uma/keys" 120
  wait_for_url "${BASE_URL}/" 120

  printf 'Verifying derived metadata via UMA: %s\n' "${DERIVED_META_URL}"
  local meta_output
  meta_output="$(uma_get "${DERIVED_META_URL}")"
  grep -F 'latest-anomaly' <<<"${meta_output}" >/dev/null
  grep -F '"http://localhost:3000/alice/derived/anomaly-alert/*"' <<<"${meta_output}" >/dev/null

  local timestamp alert_id alert_slug alert_url alert_file latest_output
  timestamp="$(date +%s)"
  alert_id="test-alert-${timestamp}"
  alert_slug="${alert_id}.ttl"
  alert_url="${ALERT_CONTAINER_URL}${alert_slug}"
  alert_file="$(mktemp)"
  trap "rm -f '${alert_file}'" EXIT

  cat >"${alert_file}" <<EOF
@prefix ex: <https://example.org/ns#> .

<> ex:type "anomaly-alert";
   ex:alertId "${alert_id}";
   ex:severity "high" .
EOF

  printf 'Writing fresh anomaly alert via UMA: %s\n' "${alert_url}"
  uma_put "${alert_url}" "${alert_file}" 'text/turtle'

  printf 'Resolving latest anomaly via UMA: %s\n' "${LATEST_ANOMALY_URL}"
  latest_output="$(uma_get "${LATEST_ANOMALY_URL}")"
  grep -F "\"${alert_id}\"" <<<"${latest_output}" >/dev/null
  grep -F 'https://example.org/ns#severity' <<<"${latest_output}" >/dev/null

  cat <<EOF
Derived verification passed:
 - GET ${DERIVED_META_URL}
 - PUT ${alert_url}
 - GET ${LATEST_ANOMALY_URL} => HTTP 200
If this fails later with derivedCount=0, inspect the CSS logs for BaseDerivationManager and compare them with ${DERIVED_META_URL}.
EOF
}

main "$@"
