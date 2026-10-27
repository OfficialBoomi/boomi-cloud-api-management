#!/usr/bin/env bash
# Shared utilities for boomi-cloud-api-management CLI tools; sourced, not executed directly.

set -euo pipefail

# --- Environment ---

load_env() {
  # Leading ./ is required: source searches $PATH for a name containing no slash.
  local env_file="./.env"
  if [[ ! -f "$env_file" ]]; then
    echo "ERROR: .env file not found in $(pwd)" >&2
    exit 1
  fi
  local _xtrace_enabled=0
  case $- in *x*) _xtrace_enabled=1 ;; esac
  # Trace off: .env assignments.
  set +x
  # shellcheck disable=SC1090
  source "$env_file"
  if (( _xtrace_enabled )); then set -x; fi
  _set_user_agent   # .env must not override the header
}

# True if the named variable is non-empty.
var_is_set() {
  local _xtrace_enabled=0
  case $- in *x*) _xtrace_enabled=1 ;; esac
  # Trace off: by-name expansion of .env values.
  set +x
  local rc=0
  [[ -n "${!1:-}" ]] || rc=1
  if (( _xtrace_enabled )); then set -x; fi
  return $rc
}

require_env() {
  local missing=() var
  for var in "$@"; do
    var_is_set "$var" || missing+=("$var")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required environment variables: ${missing[*]}" >&2
    echo "Check your .env file." >&2
    exit 1
  fi
}

require_tools() {
  local missing=() tool
  for tool in "$@"; do
    command -v "$tool" &>/dev/null || missing+=("$tool")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required tools: ${missing[*]}" >&2
    exit 1
  fi
}

CAM_REQUIRED_VARS="CAM_API_KEY CAM_API_SECRET CAM_USERNAME CAM_PASSWORD CAM_AREA_UUID"

# Setup; every script calls this once.
cam_init() {
  load_env
  # shellcheck disable=SC2086
  require_env $CAM_REQUIRED_VARS
  require_tools curl jq perl
  CAM_API_URL="${CAM_API_URL:-https://api.mashery.com}"
  CAM_API_URL="${CAM_API_URL%/}"
  CAM_STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/bc-apim"
  mkdir -p "$CAM_STATE_DIR"
  chmod 700 "$CAM_STATE_DIR"
}

# Temp file for script-built request bodies.
CAM_BODY_FILE=""
trap 'rm -f ${CAM_BODY_FILE:+"$CAM_BODY_FILE"}' EXIT
body_file() { [[ -n "$CAM_BODY_FILE" ]] || CAM_BODY_FILE=$(mktemp); }

# --- Argument handling ---

# Handles --help anywhere in the args.
help_requested() {
  local arg
  for arg in "$@"; do
    case "$arg" in --help|-h) usage; exit 0 ;; esac
  done
}

need() {
  local n="$1"; shift
  if (( $# < n )); then usage >&2; exit 1; fi
}

need_file() {
  [[ -f "$1" ]] || { echo "ERROR: file not found: $1" >&2; exit 1; }
  jq -e 'type == "object"' "$1" >/dev/null 2>&1 || { echo "ERROR: $1 is not a JSON object" >&2; exit 1; }
}

# --- Version / User-Agent ---

_skill_version() {
  cat "$(dirname "${BASH_SOURCE[0]}")/../VERSION" 2>/dev/null || echo "unknown"
}

_set_user_agent() {
  CAM_USER_AGENT="boomi-companion/boomi-cloud-api-management/$(_skill_version)"
}
_set_user_agent

# --- Field lists ---

CAM_ENDPOINT_FIELDS="id,name,allowMissingApiKey,apiKeyValueLocationKey,apiKeyValueLocations,\
apiMethodDetectionKey,apiMethodDetectionLocations,cache,\
connectionTimeoutForSystemDomainRequest,connectionTimeoutForSystemDomainResponse,\
cors,customRequestAuthenticationAdapter,dropApiKeyFromIncomingCall,\
forceGzipOfBackendCall,gzipPassthroughSupportEnabled,headersToExcludeFromIncomingCall,\
highSecurity,hostPassthroughIncludedInBackendCallHeader,inboundSslRequired,\
jsonpCallbackParameter,jsonpCallbackParameterValue,forwardedHeaders,returnedHeaders,\
methods,numberOfHttpRedirectsToFollow,outboundRequestTargetPath,\
outboundRequestTargetQueryParameters,outboundTransportProtocol,processor,\
publicDomains,requestAuthenticationType,requestPathAlias,requestProtocol,\
stringsToTrimFromApiKey,supportedHttpMethods,systemDomainAuthentication,\
systemDomains,trafficManagerDomain,useSystemDomainCredentials,\
systemDomainCredentialKey,useSystemDomainAsTarget,rateLimitHeadersEnabled,\
cookiesDuringHttpRedirectsEnabled,created,updated"
CAM_SERVICE_FIELDS="id,name,description,version,created,updated,endpoints.id,endpoints.name,endpoints.requestPathAlias"
CAM_PLAN_FIELDS="id,name,description,qpsLimitCeiling,rateLimitCeiling,rateLimitPeriod,maxNumKeysAllowed,numKeysBeforeReview,adminKeyProvisioningEnabled,selfServiceKeyProvisioningEnabled,services.id,services.name,services.endpoints.id,services.endpoints.name"

# --- Curl config ---

# Emits a curl config file on stdout for `curl -K -`.
# Usage: curl_cfg user "u:p" header "Authorization: Bearer t" | curl -K - ...
curl_cfg() {
  (( $# % 2 == 0 )) || { echo "ERROR: curl_cfg needs directive/value pairs" >&2; return 1; }
  local val
  while [[ $# -gt 1 ]]; do
    val="$2"
    val="${val//\\/\\\\}"
    val="${val//\"/\\\"}"
    printf '%s = "%s"\n' "$1" "$val"
    shift 2
  done
}

# --- Throttle ---

# 1/CAM_QPS seconds between calls, shared across script runs.
_cam_throttle() {
  local lock="$CAM_STATE_DIR/cam-throttle.lock" tries=0
  until mkdir "$lock" 2>/dev/null; do
    tries=$((tries + 1))
    if (( tries > 100 )); then rmdir "$lock" 2>/dev/null || true; tries=0; fi  # stale lock
    sleep 0.05
  done
  perl -MTime::HiRes=time,sleep -e '
    my ($f, $qps) = @ARGV; my $last = 0;
    if (open my $in, "<", $f) { $last = <$in> + 0; close $in; }
    my $wait = $last + 1 / $qps - time; sleep $wait if $wait > 0;
    open my $out, ">", $f or die "cannot write $f\n"; print $out time;
  ' "$CAM_STATE_DIR/cam-throttle.last" "${CAM_QPS:-2}"
  rmdir "$lock"
}

# --- Token ---

CAM_TOKEN=""

# Mints CAM_TOKEN once per run (password grant). Returns non-zero on failure.
cam_token() {
  (( ${#CAM_TOKEN} )) && return 0
  local _xtrace_enabled=0
  case $- in *x*) _xtrace_enabled=1 ;; esac
  # Trace off: token request credentials and response.
  set +x
  local out code body rc=0
  _cam_throttle
  out=$(curl_cfg user "${CAM_API_KEY}:${CAM_API_SECRET}" \
      data-urlencode "grant_type=password" \
      data-urlencode "username=${CAM_USERNAME}" \
      data-urlencode "password=${CAM_PASSWORD}" \
      data-urlencode "scope=${CAM_AREA_UUID}" \
    | curl -s --max-time 60 -A "$CAM_USER_AGENT" -K - -w '\n%{http_code}' \
        "$CAM_API_URL/v3/token") || out=$'\n000'
  code="${out##*$'\n'}"
  body="${out%$'\n'*}"
  [[ "$code" == 200 ]] && CAM_TOKEN=$(jq -r '.access_token // empty' <<<"$body" 2>/dev/null || true)
  if [[ -z "$CAM_TOKEN" ]]; then
    echo "ERROR: CAM token request failed (HTTP $code)." >&2
    cat <<<"$body" >&2
    echo "Check CAM_API_KEY/SECRET, CAM_USERNAME/PASSWORD, CAM_AREA_UUID." >&2
    rc=1
  fi
  if (( _xtrace_enabled )); then set -x; fi
  return $rc
}

# --- API ---

RESPONSE_BODY=""
RESPONSE_CODE=""
RESPONSE_TOTAL=""
RESPONSE_ERRCODE=""

# One request; sets the RESPONSE_* globals. Fails only when no HTTP response arrives.
_cam_request() {
  local method="$1" path="$2" body_file="${3:-}"
  cam_token || return 1
  local _xtrace_enabled=0
  case $- in *x*) _xtrace_enabled=1 ;; esac
  # Trace off: bearer token and response body.
  set +x
  local out hdrs="" rc=0 data=()
  [[ -n "$body_file" ]] && data=(--data-binary "@$body_file")
  _cam_throttle
  out=$(curl_cfg header "Authorization: Bearer $CAM_TOKEN" \
    | curl -s -i --max-time 60 -A "$CAM_USER_AGENT" -K - -X "$method" \
        -H "Content-Type: application/json" -H "Accept: application/json" \
        ${data[@]+"${data[@]}"} -w '\n%{http_code}' \
        "$CAM_API_URL/v3/rest/${path#/}") || rc=$?
  RESPONSE_CODE="${out##*$'\n'}"
  out="${out%$'\n'*}"
  while [[ "$out" == HTTP/* && "$out" == *$'\r\n\r\n'* ]]; do
    hdrs="${out%%$'\r\n\r\n'*}"
    out="${out#*$'\r\n\r\n'}"
  done
  RESPONSE_BODY="$out"
  hdrs="${hdrs//$'\r'/}"
  RESPONSE_TOTAL=$(awk -F': *' 'tolower($1)=="x-total-count"{v=$2} END{print v}' <<<"$hdrs")
  RESPONSE_ERRCODE=$(awk -F': *' 'tolower($1)=="x-mashery-error-code"{v=$2} END{print v}' <<<"$hdrs")
  if (( _xtrace_enabled )); then set -x; fi
  if (( rc != 0 )) || [[ ! "$RESPONSE_CODE" =~ ^[0-9]{3}$ || "$RESPONSE_CODE" == "000" ]]; then
    RESPONSE_CODE="000"
    echo "ERROR: could not reach $CAM_API_URL (curl exit $rc). No HTTP response received." >&2
    return 1
  fi
}

_cam_over_qps() {
  [[ "$RESPONSE_CODE" == 429 ]] && return 0
  [[ "$RESPONSE_CODE" == 403 ]] || return 1
  [[ "$RESPONSE_ERRCODE" == *QPS* ]] || body_jq -eRs 'test("QPS")' >/dev/null 2>&1
}

# Runs jq over RESPONSE_BODY: body_jq [jq args...]
body_jq() {
  local _xtrace_enabled=0 rc=0
  case $- in *x*) _xtrace_enabled=1 ;; esac
  # Trace off: response bodies can carry keys and passwords.
  set +x
  jq "$@" <<<"$RESPONSE_BODY" || rc=$?
  if (( _xtrace_enabled )); then set -x; fi
  return $rc
}

# cam_api METHOD PATH [JSON_BODY_FILE] -- PATH is relative to /v3/rest and may carry a query.
# Non-2xx after retries: prints to stderr, returns 1.
cam_api() {
  local method="$1" path="$2" body_file="${3:-}" attempt=0 reauthed=0 delay
  while :; do
    _cam_request "$method" "$path" "$body_file" || return 1
    if [[ "$RESPONSE_CODE" == 401 && $reauthed == 0 ]]; then
      CAM_TOKEN=""; reauthed=1; continue
    fi
    if _cam_over_qps && (( attempt < 4 )); then
      delay=$((1 << attempt)); attempt=$((attempt + 1))
      echo "WARN: HTTP $RESPONSE_CODE over rate limit; retrying in ${delay}s" >&2
      sleep "$delay"; continue
    fi
    break
  done
  if (( RESPONSE_CODE < 200 || RESPONSE_CODE >= 300 )); then
    echo "HTTP $RESPONSE_CODE ($method $path)" >&2
    body_jq -rR . >&2 || true
    return 1
  fi
}

# cam_get_all PATH FIELDS MODE -- MODE item: offset counts records; page: offset counts
# pages. Prints one merged array.
cam_get_all() {
  local path="$1" fields="$2" mode="$3" offset=0 sep="?" n acc="" rc=0
  [[ "$path" == *\?* ]] && sep="&"
  local _xtrace_enabled=0
  case $- in *x*) _xtrace_enabled=1 ;; esac
  # Trace off: collected pages can carry keys.
  set +x
  while :; do
    cam_api GET "${path}${sep}fields=${fields}&limit=100&offset=${offset}" || { rc=1; break; }
    acc+="$RESPONSE_BODY"$'\n'
    n=$(body_jq 'length')
    (( n < 100 )) && break
    if [[ "$mode" == item ]]; then offset=$((offset + 100)); else offset=$((offset + 1)); fi
  done
  if (( rc == 0 )); then jq -s 'add // []' <<<"$acc"; fi
  if (( _xtrace_enabled )); then set -x; fi
  return $rc
}

# --- Output helpers ---

# jq program for --argjson show: masks apikey and secret to the last 4 chars, and password fully, at any depth.
CAM_MASK='def mask($k): if $show == 1 or type != "string" then . elif $k == "password" then "********" elif length > 4 then "****" + .[-4:] else . end;
  (.. | objects) |= with_entries(if .key == "apikey" or .key == "secret" or .key == "password" then .key as $k | .value |= mask($k) else . end)'

cam_print() {
  (( ${#RESPONSE_BODY} )) || return 0
  body_jq . 2>/dev/null || body_jq -rR .
}

urlenc() { jq -Rr @uri <<<"$1"; }

# Writes a jq -n result to CAM_BODY_FILE.
json_body() {
  body_file
  jq -n "$@" > "$CAM_BODY_FILE"
}

# Rejects child arrays in update bodies.
refuse_child_arrays() {
  need_file "$1"
  local key
  key=$(jq -r '[keys[] | select(. == "endpoints" or . == "plans" or . == "services" or . == "methods")] | first // empty' "$1")
  [[ -z "$key" ]] && return 0
  echo "ERROR: update body contains '$key'. A PUT replaces that array wholesale." >&2
  case "$key" in
    endpoints) echo "  Use cam-endpoint.sh create/update instead." >&2 ;;
    plans)     echo "  Use cam-package.sh plan-create/plan-update instead." >&2 ;;
    services)  echo "  Use cam-package.sh plan-add-endpoint/plan-remove-endpoint instead." >&2 ;;
    methods)   echo "  Methods are not scripted; use cam-api.sh on /services/{sid}/endpoints/{eid}/methods." >&2 ;;
  esac
  exit 1
}
