#!/usr/bin/env bash
# CAM endpoints under a service.

source "$(dirname "$0")/cam-common.sh"

usage() {
  cat <<'USAGE'
Usage: cam-endpoint.sh <subcommand> [args]

Subcommands:
  list   SID
  get    SID EID            full field set; backend password masked
  create SID FILE           prints the endpoint re-read with full fields
  update SID EID FILE       partial PUT; scalars only (no methods array);
                            prints the endpoint re-read with full fields

Endpoints serve live traffic. Confirm updates with the user.
Reads CAM_* from .env.
USAGE
}
[[ -z "${1:-}" ]] && { usage; exit 0; }
help_requested "$@"
sub="$1"; shift

cam_init

# Prints the endpoint with the backend password masked.
print_endpoint() {
  body_jq '
    if (.systemDomainAuthentication | type) == "object" and .systemDomainAuthentication.password
    then .systemDomainAuthentication.password = "********" else . end'
}

# Re-reads with full fields.
get_endpoint() {
  cam_api GET "services/$1/endpoints/$2?fields=$CAM_ENDPOINT_FIELDS"
  print_endpoint
}

case "$sub" in
  list)
    need 1 "$@"
    cam_get_all "services/$1/endpoints" "id,name,requestPathAlias,publicDomains,systemDomains,outboundRequestTargetPath" item
    ;;
  get)
    need 2 "$@"; get_endpoint "$1" "$2"
    ;;
  create)
    need 2 "$@"; need_file "$2"
    cam_api POST "services/$1/endpoints" "$2"
    get_endpoint "$1" "$(body_jq -r '.id')"
    ;;
  update)
    need 3 "$@"; refuse_child_arrays "$3"
    cam_api PUT "services/$1/endpoints/$2" "$3"
    get_endpoint "$1" "$2"
    ;;
  *) usage >&2; exit 1 ;;
esac
