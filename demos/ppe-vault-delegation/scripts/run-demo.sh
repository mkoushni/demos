#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Praxis Contributors

set -euo pipefail

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATEWAY_URL="${GATEWAY_URL:-http://127.0.0.1:8090/}"

call_tool() {
  subject="$1"
  tool="$2"
  token="$(<"$DEMO_DIR/.state/$subject.jwt")"
  jq -cn --arg tool "$tool" '{jsonrpc:"2.0",id:1,method:"tools/call",params:{name:$tool,arguments:{}}}' \
    | curl -fsS \
        -H 'content-type: application/json' \
        -H "X-User-Token: $token" \
        --data-binary @- \
        "$GATEWAY_URL"
}

echo "[1/3] alice: enrolled credential reaches GitHub"
alice_response="$(call_tool alice github_whoami)"
printf '%s\n' "$alice_response" | jq .
printf '%s' "$alice_response" | jq -e '.result.content[0].text | fromjson | .login | length > 0' >/dev/null

echo "[2/3] bob: no enrolled credential"
github_before="$(curl -fsS http://127.0.0.1:9100/stats | jq -er '.github_calls')"
bob_response="$(call_tool bob github_whoami || true)"
printf '%s\n' "$bob_response" | jq .
printf '%s' "$bob_response" | grep -Fq 'delegation.vault_secret_not_found'
github_after="$(curl -fsS http://127.0.0.1:9100/stats | jq -er '.github_calls')"
[ "$github_before" = "$github_after" ] || { echo "unenrolled user contacted GitHub" >&2; exit 1; }

echo "[3/3] policy deny: no Vault or GitHub dependency call"
vault_before="$(docker compose -f "$DEMO_DIR/docker-compose.yml" logs --no-color vault 2>/dev/null | grep -c '"type":"request"' || true)"
github_before="$(curl -fsS http://127.0.0.1:9100/stats | jq -er '.github_calls')"
deny_response="$(call_tool alice github_denied || true)"
printf '%s\n' "$deny_response" | jq .
printf '%s' "$deny_response" | grep -Fq 'demo.policy_denied'
vault_after="$(docker compose -f "$DEMO_DIR/docker-compose.yml" logs --no-color vault 2>/dev/null | grep -c '"type":"request"' || true)"
github_after="$(curl -fsS http://127.0.0.1:9100/stats | jq -er '.github_calls')"
[ "$vault_before" = "$vault_after" ] || { echo "policy deny contacted Vault" >&2; exit 1; }
[ "$github_before" = "$github_after" ] || { echo "policy deny contacted GitHub" >&2; exit 1; }

echo "demo passed"
