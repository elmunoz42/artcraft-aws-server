#!/usr/bin/env bash
# Check the MCP endpoint end to end. Run on the instance, or anywhere that can reach it:
#
#   scripts/mcp-smoke-test.sh                          # http://127.0.0.1:$MCP_PORT, token from .env
#   MCP_URL=http://10.0.0.5:8811 MCP_TOKEN=... scripts/mcp-smoke-test.sh
#
# Checks: no token -> 401, wrong token -> 401, MCP initialize, tools/list, the bridge sees
# the installed apps, PhotoCraft writes a PNG into outputs/, and /files serves it back.
set -Eeuo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

url="${MCP_URL:-http://127.0.0.1:$(env_get MCP_PORT 8811)}"
token="$(env_get MCP_TOKEN)"
[ -n "${token}" ] || die "MCP_TOKEN is not set"
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp}"' EXIT
pass=0; fail=0
ok() { echo "PASS  $*"; pass=$((pass + 1)); }
bad() { echo "FAIL  $*"; fail=$((fail + 1)); }

code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "${url}/mcp" || true)"
if [ "${code}" = "401" ]; then ok "no token is refused (401)"; else bad "no token returned ${code}, expected 401"; fi
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -H 'Authorization: Bearer wrong' "${url}/mcp" || true)"
if [ "${code}" = "401" ]; then ok "wrong token is refused (401)"; else bad "wrong token returned ${code}, expected 401"; fi

# One JSON-RPC call over Streamable HTTP. The reply is JSON or a one-event SSE stream.
session=""
rpc() {
  local body="$1" out="$2" hdrs=()
  [ -n "${session}" ] && hdrs=(-H "Mcp-Session-Id: ${session}")
  curl -sS --max-time "${3:-60}" -D "${tmp}/headers" -o "${tmp}/raw" \
    -H "Authorization: Bearer ${token}" -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' "${hdrs[@]}" -d "${body}" "${url}/mcp" || return 1
  if grep -q '^data:' "${tmp}/raw"; then grep '^data:' "${tmp}/raw" | tail -n1 | cut -c6- > "${out}"; else cp "${tmp}/raw" "${out}"; fi
}

if rpc '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"artcraft-cloud-smoke-test","version":"1"}}}' "${tmp}/init" \
   && grep -q '"serverInfo"' "${tmp}/init"; then
  ok "initialize"
  session="$(grep -i '^mcp-session-id:' "${tmp}/headers" | tail -n1 | cut -d: -f2- | tr -d ' \r' || true)"
  rpc '{"jsonrpc":"2.0","method":"notifications/initialized"}' "${tmp}/note" 20 || true
else
  bad "initialize: $(head -c 300 "${tmp}/raw" 2>/dev/null)"
fi

if rpc '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' "${tmp}/tools" && grep -q '"artcraft_run"' "${tmp}/tools"; then
  ok "tools/list has $(grep -o '"name":"artcraft_[a-z]*"' "${tmp}/tools" | sort -u | wc -l | tr -d ' ') artcraft tools"
else
  bad "tools/list: $(head -c 300 "${tmp}/tools" 2>/dev/null)"
fi

if rpc '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"artcraft_apps","arguments":{}}}' "${tmp}/apps" && grep -q 'photocraft' "${tmp}/apps"; then
  ok "artcraft_apps lists photocraft"
else
  bad "artcraft_apps: $(head -c 300 "${tmp}/apps" 2>/dev/null)"
fi

name="smoke-test-$(date +%s).png"
call="{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"artcraft_run\",\"arguments\":{\"app\":\"photocraft\",\"steps\":[{\"id\":\"select.all\"}],\"params\":{\"document\":{\"width\":640,\"height\":360}},\"output\":\"/work/outputs/${name}\"}}}"
if rpc "${call}" "${tmp}/run" 180; then
  size="$(curl -s -o "${tmp}/out.png" -w '%{size_download}' --max-time 30 -H "Authorization: Bearer ${token}" "${url}/files/${name}" || echo 0)"
  if [ "${size}" -gt 0 ] && head -c 8 "${tmp}/out.png" | grep -q 'PNG'; then
    ok "photocraft wrote outputs/${name} (${size} bytes) and /files served it"
  else
    bad "export not found at /files/${name}; tool said: $(head -c 400 "${tmp}/run")"
  fi
else
  bad "artcraft_run request failed"
fi
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "${url}/files/${name}" || true)"
if [ "${code}" = "401" ]; then ok "/files without a token is refused (401)"; else bad "/files without a token returned ${code}"; fi

echo "${pass} passed, ${fail} failed"
[ "${fail}" -eq 0 ]
