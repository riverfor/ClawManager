#!/usr/bin/env bash
set -euo pipefail

# 注意:不要用 USERNAME / PASSWORD 这类泛名,Linux 桌面 / login shell 通常已经
# 导出 USERNAME=<当前系统用户>,会盖掉默认值。改用 API_ 前缀。
BASE_URL="${BASE_URL:-http://127.0.0.1:32576}"
API_USER="${API_USER:-admin}"
API_PASSWORD="${API_PASSWORD:-admin123}"
INSTANCE_ID="${INSTANCE_ID:-1}"
CONTAINER="${CONTAINER:-desktop}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-120}"

# openclaw onboard 需要 MINIMAX_API_KEY,必须由调用方提供。
MINIMAX_API_KEY="${MINIMAX_API_KEY:-}"
if [[ -z "${MINIMAX_API_KEY}" ]]; then
  echo "MINIMAX_API_KEY is required (export it before running)" >&2
  exit 2
fi

# exec API 不走 shell,所以原先 bash 里 "VAR=val cmd ..." 的隐式 env 形式
# 要显式翻成 env 命令。用 jq 构造数组,避免 key 中含特殊字符时破 JSON。
CMD_JSON="${CMD_JSON:-$(jq -nc --arg key "${MINIMAX_API_KEY}" '
  [
    "env", "MINIMAX_API_KEY=" + $key,
    "openclaw", "onboard",
    "--non-interactive",
    "--mode", "local",
    "--auth-choice", "minimax-cn-api",
    "--accept-risk",
    "--skip-bootstrap",
    "--skip-skills",
    "--skip-search",
    "--skip-health",
    "--skip-channels",
    "--skip-ui",
    "--gateway-bind", "loopback"
  ]')}"

LOGIN_RESP=$(curl -sS "${BASE_URL}/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${API_USER}\",\"password\":\"${API_PASSWORD}\"}")

TOKEN=$(printf '%s' "${LOGIN_RESP}" | jq -r '.data.access_token // empty')

if [[ -z "${TOKEN}" ]]; then
  echo "login failed (user=${API_USER}); response was:" >&2
  printf '%s\n' "${LOGIN_RESP}" >&2
  exit 1
fi

BODY=$(jq -nc \
  --arg container "${CONTAINER}" \
  --argjson cmd "${CMD_JSON}" \
  --argjson timeout "${TIMEOUT_SECONDS}" \
  '{container: $container, command: $cmd, timeout_seconds: $timeout}')

curl -sS "${BASE_URL}/api/v1/instances/${INSTANCE_ID}/exec" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  --data-binary "${BODY}" \
  | jq .
