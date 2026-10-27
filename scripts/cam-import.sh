#!/usr/bin/env bash
# Transform an OpenAPI/Swagger document into a CAM service definition.

source "$(dirname "$0")/cam-common.sh"

usage() {
  cat <<'USAGE'
Usage: cam-import.sh FILE --public-domain DOMAIN [--format oas3|swagger2] [--create]

  FILE             OpenAPI 3 (default) or Swagger 2 document, JSON
  --public-domain  a domain already whitelisted in the area (cam-domain.sh list)
  --format         source format; default oas3
  --create         POST the transformed document to /services

Without --create, prints the full transform response (document + errors).
validationErrors and feasibilityErrors are also summarized on stderr.
Reads CAM_* from .env.
USAGE
}
[[ -z "${1:-}" ]] && { usage; exit 0; }
help_requested "$@"

file="" format="oas3" domain="" create=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --format)        format="${2:-}"; shift 2 ;;
    --public-domain) domain="${2:-}"; shift 2 ;;
    --create)        create=1; shift ;;
    -*) echo "ERROR: unexpected option '$1'" >&2; usage >&2; exit 1 ;;
    *)  file="$1"; shift ;;
  esac
done
[[ -n "$file" && -n "$domain" ]] || { usage >&2; exit 1; }
[[ "$format" == oas3 || "$format" == swagger2 ]] || { echo "ERROR: --format must be oas3 or swagger2" >&2; exit 1; }
need_file "$file"

cam_init

cam_api POST "transform?sourceFormat=$format&targetFormat=masheryapi&publicDomain=$(urlenc "$domain")" "$file"
body_jq -r '
  (.validationErrors // [] | .[] | "validationError: \(.)"),
  (.feasibilityErrors // [] | .[] | "feasibilityError: \(.)")' >&2

if (( ! create )); then cam_print; exit 0; fi

body_file
body_jq -e '.document // empty' > "$CAM_BODY_FILE" \
  || { echo "ERROR: transform returned no document; nothing created." >&2; exit 1; }
cam_api POST services "$CAM_BODY_FILE"
cam_print
