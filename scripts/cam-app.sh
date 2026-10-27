#!/usr/bin/env bash
# CAM members (read-only) and applications.

source "$(dirname "$0")/cam-common.sh"

usage() {
  cat <<'USAGE'
Usage: cam-app.sh <subcommand> [args]

Subcommands:
  members [USERNAME]       list members; USERNAME is an exact match
  list    [MEMBER_ID]      all applications, or one member's
  get     AID
  create  USERNAME NAME    create an application owned by an existing member

Reads CAM_* from .env.
USAGE
}
[[ -z "${1:-}" ]] && { usage; exit 0; }
help_requested "$@"
sub="$1"; shift

cam_init

APP_FIELDS="id,name,status,description,username,created,updated"

members() {
  local path="members"
  [[ -n "${1:-}" ]] && path="members?filter=username:$(urlenc "$1")"
  cam_get_all "$path" "id,username,email" page
}

case "$sub" in
  members) members "${1:-}"; exit 0 ;;
  list)
    path="applications"
    [[ -n "${1:-}" ]] && path="members/$1/applications"
    cam_get_all "$path" "id,name,status,username" page; exit 0
    ;;
  get)    need 1 "$@"; cam_api GET "applications/$1?fields=$APP_FIELDS" ;;
  create)
    need 2 "$@"
    mid=$(members "$1" | jq -r '.[0].id // empty')
    [[ -n "$mid" ]] || { echo "ERROR: no member with username '$1'." >&2; exit 1; }
    json_body --arg n "$2" --arg u "$1" '{name: $n, username: $u}'
    cam_api POST "members/$mid/applications" "$CAM_BODY_FILE"
    ;;
  *) usage >&2; exit 1 ;;
esac
cam_print
