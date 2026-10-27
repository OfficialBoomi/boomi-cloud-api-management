#!/usr/bin/env bash
# CAM package keys (application-scoped API keys).

# Trace off for the whole file: package keys and secrets.
set +x

source "$(dirname "$0")/cam-common.sh"

usage() {
  cat <<'USAGE'
Usage: cam-key.sh <subcommand> [args]

Subcommands:
  list    [AID] [--show]   all keys, or one application's
  create  AID PID PLID [--show]
                           CAM generates the key
  enable  KID              status -> active
  disable KID              status -> disabled
  call    KID URL [--header NAME | --param NAME]
                           consumer GET through the gateway with the key
                           (default: header api_key); key masked in output

Output masks apikey/secret to the last 4 chars; list and create take --show.
One key per application per package/plan (400 Duplicate Object otherwise).
A new key can take some time to become active. Reads CAM_* from .env.
USAGE
}
[[ -z "${1:-}" ]] && { usage; exit 0; }
help_requested "$@"
sub="$1"; shift

show=0 args=()
if [[ "$sub" == list || "$sub" == create ]]; then
  for a in "$@"; do
    case "$a" in
      --show) show=1 ;;
      -*) echo "ERROR: unexpected option '$a'" >&2; exit 1 ;;
      *) args+=("$a") ;;
    esac
  done
  set -- ${args[@]+"${args[@]}"}
fi

cam_init

KEY_FIELDS="id,apikey,secret,status,created,updated,application.id,application.name,package.id,package.name,plan.id,plan.name"

set_status() {
  json_body --arg s "$2" '{status: $s}'
  cam_api PUT "packageKeys/$1" "$CAM_BODY_FILE"
  body_jq --argjson show 0 "$CAM_MASK"
  exit 0
}

case "$sub" in
  list)
    path="packageKeys"
    [[ -n "${1:-}" ]] && path="applications/$1/packageKeys"
    cam_get_all "$path" "$KEY_FIELDS" page | jq --argjson show "$show" "$CAM_MASK"
    exit 0
    ;;
  create)
    need 3 "$@"
    # Empty apikey: CAM generates it.
    json_body --arg p "$2" --arg pl "$3" \
      '{apikey: "", secret: "", status: "active", limits: [], package: {id: $p}, plan: {id: $pl}}'
    cam_api POST "applications/$1/packageKeys" "$CAM_BODY_FILE"
    body_jq --argjson show "$show" "$CAM_MASK"
    status=$(body_jq -r '.status // "unknown"')
    echo "Key status: $status. If 'waiting', run: cam-key.sh enable <KID>. A new key can take some time to become active." >&2
    exit 0
    ;;
  enable)  need 1 "$@"; set_status "$1" active ;;
  disable) need 1 "$@"; set_status "$1" disabled ;;
  call)
    need 2 "$@"; kid="$1" url="$2"; shift 2
    loc=header name=api_key
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --header) loc=header name="${2:?--header needs a NAME}"; shift 2 ;;
        --param)  loc=param  name="${2:?--param needs a NAME}";  shift 2 ;;
        *) echo "ERROR: unexpected argument '$1'" >&2; exit 1 ;;
      esac
    done
    cam_api GET "packageKeys/$kid?fields=id,apikey"
    key=$(body_jq -r '.apikey // empty')
    [[ -n "$key" ]] || { echo "ERROR: key $kid has no apikey." >&2; exit 1; }
    enc=$(jq -Rr @uri <<<"$key")
    if [[ "$loc" == header ]]; then
      cfg=$(curl_cfg header "$name: $key" url "$url")
    else
      sep='?'; [[ "$url" == *\?* ]] && sep='&'
      cfg=$(curl_cfg url "$url$sep$name=$enc")
    fi
    out=$(printf '%s\n' "$cfg" | curl -sS -i --max-time 60 -A "$CAM_USER_AGENT" -K -) || true
    out="${out//"$key"/****${key: -4}}"
    out="${out//"$enc"/****${key: -4}}"
    printf '%s\n' "$out" | head -c 4000; echo
    exit 0
    ;;
  *) usage >&2; exit 1 ;;
esac
cam_print
