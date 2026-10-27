#!/usr/bin/env bash
# Raw CAM V3 REST call for anything not scripted.

source "$(dirname "$0")/cam-common.sh"

usage() {
  cat <<'USAGE'
Usage: cam-api.sh METHOD PATH [BODY_FILE] [--show]

  METHOD     GET | POST | PUT  (DELETE is refused; deletes are done in Control Center)
  PATH       relative to /v3/rest, query allowed, e.g.
             'services/SID/endpoints/EID/methods?fields=id,name'
  BODY_FILE  JSON file for POST/PUT
  --show     print apikey, secret, and password values unmasked

Pass fields= with id in it: without fields= CAM returns only id/name/created/updated,
and fields=* returns an empty object.
Prints the response body; X-Total-Count (if any) goes to stderr.
USAGE
}
[[ -z "${1:-}" ]] && { usage; exit 0; }
help_requested "$@"

show=0 args=()
for a in "$@"; do
  case "$a" in
    --show) show=1 ;;
    -*) echo "ERROR: unexpected option '$a'" >&2; exit 1 ;;
    *) args+=("$a") ;;
  esac
done
set -- ${args[@]+"${args[@]}"}

need 2 "$@"
case "$1" in
  GET|POST|PUT) ;;
  *) echo "ERROR: method '$1' not allowed. Deletes are done by the user in Control Center." >&2; exit 1 ;;
esac
[[ -n "${3:-}" ]] && need_file "$3"

cam_init
cam_api "$1" "$2" "${3:-}"
[[ -n "$RESPONSE_TOTAL" ]] && echo "X-Total-Count: $RESPONSE_TOTAL" >&2
(( ${#RESPONSE_BODY} )) || exit 0
body_jq --argjson show "$show" "$CAM_MASK" 2>/dev/null || body_jq -rR .
