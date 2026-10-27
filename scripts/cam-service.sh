#!/usr/bin/env bash
# CAM services (API definitions).

source "$(dirname "$0")/cam-common.sh"

usage() {
  cat <<'USAGE'
Usage: cam-service.sh <subcommand> [args]

Subcommands:
  list                 all services with their endpoint ids/names/paths
  get    SID
  create FILE          JSON body; may include inline endpoints
  update SID FILE      partial PUT; scalars only (no endpoints array)

Reads CAM_* from .env.
USAGE
}
[[ -z "${1:-}" ]] && { usage; exit 0; }
help_requested "$@"
sub="$1"; shift

cam_init

case "$sub" in
  list)   cam_get_all services "$CAM_SERVICE_FIELDS" item; exit 0 ;;
  get)    need 1 "$@"; cam_api GET "services/$1?fields=$CAM_SERVICE_FIELDS" ;;
  # Re-read with full fields.
  create) need 1 "$@"; need_file "$1"; cam_api POST services "$1"
          cam_api GET "services/$(body_jq -r .id)?fields=$CAM_SERVICE_FIELDS" ;;
  update) need 2 "$@"; refuse_child_arrays "$2"; cam_api PUT "services/$1" "$2"
          cam_api GET "services/$1?fields=$CAM_SERVICE_FIELDS" ;;
  *) usage >&2; exit 1 ;;
esac
cam_print
