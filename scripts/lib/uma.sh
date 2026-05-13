#!/usr/bin/env bash

if [[ -n "${UMA_SH_LOADED:-}" ]]; then
  return 0
fi
readonly UMA_SH_LOADED=1

BASE_URL="${BASE_URL:-http://localhost:3000}"
UMA_URL="${UMA_URL:-http://localhost:4000}"
UMA_CLAIM_WEBID="${UMA_CLAIM_WEBID:-http%3A%2F%2Flocalhost%3A3000%2Falice%2Fprofile%2Fcard%23me}"
UMA_CLAIM_TOKEN_FORMAT="${UMA_CLAIM_TOKEN_FORMAT:-urn:solidlab:uma:claims:formats:webid}"

wait_for_url() {
  local url="$1"
  local attempts="${2:-120}"
  local attempt

  for (( attempt = 1; attempt <= attempts; attempt++ )); do
    if curl -sS -o /dev/null "${url}"; then
      return 0
    fi
    sleep 1
  done

  printf 'Timed out waiting for %s\n' "${url}" >&2
  return 1
}

uma__extract_ticket() {
  local headers_file="$1"

  tr -d '\r' <"${headers_file}" | sed -n 's/^WWW-Authenticate: .*ticket="\([^"]*\)".*/\1/p' | head -n 1
}

uma__extract_token() {
  local body_file="$1"

  sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p' "${body_file}" | head -n 1
}

uma__curl_request() {
  local method="$1"
  local url="$2"
  local headers_file="$3"
  local body_file="$4"
  local auth_header="${5:-}"
  local payload_file="${6:-}"
  local content_type="${7:-}"
  local status
  local curl_args=(
    -sS
    -D "${headers_file}"
    -o "${body_file}"
    -X "${method}"
  )

  if [ -n "${auth_header}" ]; then
    curl_args+=(-H "${auth_header}")
  fi

  if [ -n "${content_type}" ]; then
    curl_args+=(-H "content-type: ${content_type}")
  fi

  if [ -n "${payload_file}" ]; then
    curl_args+=(--data-binary "@${payload_file}")
  fi

  status="$(curl "${curl_args[@]}" -w '%{http_code}' "${url}")"
  printf '%s' "${status}"
}

uma__exchange_ticket() {
  local ticket="$1"
  local token_body
  local token_status
  local token_json

  token_body="$(mktemp)"
  trap "rm -f '${token_body}'" RETURN

  token_json="$(mktemp)"
  printf '%s' \
    "{\"grant_type\":\"urn:ietf:params:oauth:grant-type:uma-ticket\",\"ticket\":\"${ticket}\",\"claim_token\":\"${UMA_CLAIM_WEBID}\",\"claim_token_format\":\"${UMA_CLAIM_TOKEN_FORMAT}\"}" \
    >"${token_json}"
  trap "rm -f '${token_body}' '${token_json}'" RETURN

  token_status="$(curl -sS -o "${token_body}" -X POST \
    -H 'content-type: application/json' \
    --data-binary "@${token_json}" \
    -w '%{http_code}' \
    "${UMA_URL}/uma/token")"

  if [[ ! "${token_status}" =~ ^20[0-9]$ ]]; then
    printf 'UMA token exchange failed for ticket %s: HTTP %s\n' "${ticket}" "${token_status}" >&2
    cat "${token_body}" >&2
    return 1
  fi

  local token
  token="$(uma__extract_token "${token_body}")"
  if [ -z "${token}" ]; then
    printf 'UMA token exchange succeeded but no access_token was returned for ticket %s\n' "${ticket}" >&2
    cat "${token_body}" >&2
    return 1
  fi

  printf '%s' "${token}"
}

uma__request() {
  local method="$1"
  local url="$2"
  local expected_regex="$3"
  local payload_file="${4:-}"
  local content_type="${5:-}"
  local challenge_headers
  local challenge_body
  local auth_headers
  local auth_body
  local challenge_status
  local auth_status
  local ticket
  local token

  challenge_headers="$(mktemp)"
  challenge_body="$(mktemp)"
  auth_headers="$(mktemp)"
  auth_body="$(mktemp)"
  trap "rm -f '${challenge_headers}' '${challenge_body}' '${auth_headers}' '${auth_body}'" RETURN

  challenge_status="$(uma__curl_request \
    "${method}" \
    "${url}" \
    "${challenge_headers}" \
    "${challenge_body}" \
    '' \
    "${payload_file}" \
    "${content_type}")"

  if [[ "${challenge_status}" =~ ${expected_regex} ]]; then
    cat "${challenge_body}"
    return 0
  fi

  ticket="$(uma__extract_ticket "${challenge_headers}")"
  if [ -z "${ticket}" ]; then
    printf 'No UMA ticket returned for %s %s: HTTP %s\n' "${method}" "${url}" "${challenge_status}" >&2
    cat "${challenge_headers}" >&2
    cat "${challenge_body}" >&2
    return 1
  fi

  token="$(uma__exchange_ticket "${ticket}")"
  auth_status="$(uma__curl_request \
    "${method}" \
    "${url}" \
    "${auth_headers}" \
    "${auth_body}" \
    "Authorization: Bearer ${token}" \
    "${payload_file}" \
    "${content_type}")"

  if [[ ! "${auth_status}" =~ ${expected_regex} ]]; then
    printf 'UMA authorized request failed for %s %s: HTTP %s\n' "${method}" "${url}" "${auth_status}" >&2
    cat "${auth_headers}" >&2
    cat "${auth_body}" >&2
    return 1
  fi

  cat "${auth_body}"
}

uma_get() {
  local url="$1"
  uma__request GET "${url}" '^200$'
}

uma_put() {
  local url="$1"
  local payload_file="$2"
  local content_type="$3"
  uma__request PUT "${url}" '^(200|201|204|205)$' "${payload_file}" "${content_type}" >/dev/null
}

uma_put_empty() {
  local url="$1"
  uma__request PUT "${url}" '^(200|201|204|205)$' >/dev/null
}

uma_patch() {
  local url="$1"
  local payload_file="$2"
  uma__request PATCH "${url}" '^(200|204|205)$' "${payload_file}" 'application/sparql-update' >/dev/null
}
