#!/usr/bin/env bash
set -euo pipefail

wait_for_url() {
  local url="$1"
  local attempts="${2:-120}"
  local i
  for (( i=1; i<=attempts; i++ )); do
    if curl -sS -o /dev/null "$url"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

if ! wait_for_url "http://localhost:4000/uma/keys" 120; then
  echo "UMA did not become ready in time" >&2
  exit 1
fi

if ! wait_for_url "http://localhost:3000/" 120; then
  echo "CSS did not become ready in time" >&2
  exit 1
fi

sleep 8

create_with_uma() {
  local target="$1"
  local body="${2:-}"
  local content_type="${3:-}"
  local mode="${4:-PUT}"
  local attempts="${5:-60}"
  local i

  for (( i=1; i<=attempts; i++ )); do
    local r t j tok
    if [ -n "$body" ]; then
      r="$(curl -i -sS -X "$mode" -H "content-type: $content_type" --data-binary @"$body" "$target" || true)"
    else
      r="$(curl -i -sS -X "$mode" "$target" || true)"
    fi
    t="$(printf '%s\n' "$r" | tr -d '\r' | sed -n 's/^WWW-Authenticate: .*ticket="\([^"]*\)".*/\1/p')"
    if [ -z "$t" ]; then
      sleep 1
      continue
    fi

    j="$(curl -sS -X POST http://localhost:4000/uma/token -H 'content-type: application/json' \
      --data "{\"grant_type\":\"urn:ietf:params:oauth:grant-type:uma-ticket\",\"ticket\":\"$t\",\"claim_token\":\"http%3A%2F%2Flocalhost%3A3000%2Falice%2Fprofile%2Fcard%23me\",\"claim_token_format\":\"urn:solidlab:uma:claims:formats:webid\"}" || true)"
    tok="$(printf '%s\n' "$j" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')"
    if [ -z "$tok" ]; then
      sleep 1
      continue
    fi

    if [ -n "$body" ]; then
      if curl -sS -o /dev/null -X "$mode" -H "Authorization: Bearer $tok" -H "content-type: $content_type" \
        --data-binary @"$body" "$target"; then
        return 0
      fi
    else
      if curl -sS -o /dev/null -X "$mode" -H "Authorization: Bearer $tok" "$target"; then
        return 0
      fi
    fi

    sleep 1
  done

  echo "Failed bootstrap request for $target" >&2
  return 1
}

create_with_uma "http://localhost:3000/alice/spo2/" "" "" "PUT" 60
create_with_uma "http://localhost:3000/alice/derived/" "" "" "PUT" 60
create_with_uma "http://localhost:3000/alice/derived/.meta" "packages/css/config/derived-spo2.meta.ttl" "text/turtle" "PUT" 60

echo "Bootstrap complete: /alice/spo2/, /alice/derived/, /alice/derived/.meta"
