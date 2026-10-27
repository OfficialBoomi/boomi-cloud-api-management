#!/usr/bin/env bash
# CAM area domains.

source "$(dirname "$0")/cam-common.sh"

usage() {
  cat <<'USAGE'
Usage: cam-domain.sh <subcommand> [args]

Subcommands:
  list
  create DOMAIN [DESCRIPTION]

WARNING: domains cannot be deleted via the API. Confirm the exact hostname
with the user before create. Reads CAM_* from .env.
USAGE
}
[[ -z "${1:-}" ]] && { usage; exit 0; }
help_requested "$@"
sub="$1"; shift

cam_init

case "$sub" in
  list)
    cam_get_all domains "id,domain,status,description" item; exit 0
    ;;
  create)
    need 1 "$@"
    json_body --arg d "$1" --arg desc "${2:-}" \
      '{domain: $d, status: "active"} + (if $desc == "" then {} else {description: $desc} end)'
    cam_api POST domains "$CAM_BODY_FILE"
    ;;
  *) usage >&2; exit 1 ;;
esac
cam_print
