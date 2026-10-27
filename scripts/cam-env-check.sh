#!/usr/bin/env bash
# Verify .env vars, get a CAM token, and make one read call.

source "$(dirname "$0")/cam-common.sh"

usage() {
  cat <<'USAGE'
Usage: cam-env-check.sh [--help]

Reports each CAM_* variable as SET/UNSET, requests a V3 token, then calls
GET /services?limit=1. Prints OK or FAIL. Reads CAM_* from .env.
USAGE
}
help_requested "$@"

load_env
echo "=== Variables ==="
for v in $CAM_REQUIRED_VARS CAM_API_URL CAM_QPS; do
  if var_is_set "$v"; then echo "  $v=SET"; else echo "  $v=UNSET"; fi
done
cam_init

echo "=== Token ==="
if ! cam_token; then echo "  FAIL" >&2; exit 1; fi
echo "  OK"

echo "=== API ==="
echo "  GET $CAM_API_URL/v3/rest/services?limit=1"
if ! cam_api GET "services?limit=1&fields=id,name"; then echo "  FAIL" >&2; exit 1; fi
echo "  HTTP $RESPONSE_CODE OK (${RESPONSE_TOTAL:-?} services in area)"
