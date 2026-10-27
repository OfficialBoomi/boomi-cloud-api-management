#!/usr/bin/env bash
# CAM packages and plans, including which endpoints a plan grants.

source "$(dirname "$0")/cam-common.sh"

usage() {
  cat <<'USAGE'
Usage: cam-package.sh <subcommand> [args]

Packages:
  list
  get    PID                     includes plan ids/names
  create FILE
  update PID FILE                partial PUT; scalars only (no plans array)

Plans:
  plan-create PID FILE           may include inline services[] with endpoints
  plan-get    PID PLID
  plan-update PID PLID FILE      partial PUT; scalars only (no services array)
  plan-add-endpoint    PID PLID SID EID
  plan-remove-endpoint PID PLID SID EID

Omit notifyDeveloperPeriod to get the default ("day"); "never" fails with a
misleading 400. Reads CAM_* from .env.
USAGE
}
[[ -z "${1:-}" ]] && { usage; exit 0; }
help_requested "$@"
sub="$1"; shift

cam_init

PACKAGE_FIELDS="id,name,description,notifyDeveloperPeriod,created,updated,plans.id,plans.name"

refuse_never() {
  if [[ "$(jq -r '.notifyDeveloperPeriod // empty' "$1")" == never ]]; then
    echo "ERROR: notifyDeveloperPeriod \"never\" returns a misleading 400. Omit it (defaults to day)." >&2
    exit 1
  fi
}

get_plan() { cam_api GET "packages/$1/plans/$2?fields=$CAM_PLAN_FIELDS"; }

# Plan services[] with one endpoint added.
ADD_FILTER='
  (.services // []) as $s
  | (if any($s[]; .id == $sid) then $s
     else $s + [{id: $sid, endpoints: []}] end)
  | {services: map({id, endpoints: (((.endpoints // []) | map({id}))
      + (if .id == $sid then [{id: $eid}] else [] end) | unique_by(.id))})}'

# Plan services[] with one endpoint removed; drops an emptied service.
REMOVE_FILTER='
  {services: [(.services // [])[]
    | .id as $this
    | {id, endpoints: [(.endpoints // [])[] | select($this != $sid or .id != $eid) | {id}]}
    | select(.id != $sid or (.endpoints | length) > 0)]}'

# Rewrites a plan's full services[] list, then re-reads the plan.
edit_plan_endpoints() {
  local mode="$1" pid="$2" plid="$3" sid="$4" eid="$5" filter="$ADD_FILTER"
  get_plan "$pid" "$plid"
  if [[ "$mode" == remove ]]; then
    filter="$REMOVE_FILTER"
    body_jq -e --arg sid "$sid" --arg eid "$eid" \
      'any(.services[]?; .id == $sid and any(.endpoints[]?; .id == $eid))' >/dev/null \
      || { echo "ERROR: endpoint $eid of service $sid is not in plan $plid." >&2; exit 1; }
  fi
  body_file
  body_jq --arg sid "$sid" --arg eid "$eid" "$filter" > "$CAM_BODY_FILE"
  cam_api PUT "packages/$pid/plans/$plid" "$CAM_BODY_FILE"
  get_plan "$pid" "$plid"
}

case "$sub" in
  list)   cam_get_all packages "id,name,description,created,updated" item; exit 0 ;;
  get)    need 1 "$@"; cam_api GET "packages/$1?fields=$PACKAGE_FIELDS" ;;
  create) need 1 "$@"; need_file "$1"; refuse_never "$1"; cam_api POST packages "$1" ;;
  update) need 2 "$@"; refuse_child_arrays "$2"; refuse_never "$2"; cam_api PUT "packages/$1" "$2" ;;
  plan-create) need 2 "$@"; need_file "$2"; cam_api POST "packages/$1/plans" "$2" ;;
  plan-get)    need 2 "$@"; get_plan "$1" "$2" ;;
  plan-update) need 3 "$@"; refuse_child_arrays "$3"; cam_api PUT "packages/$1/plans/$2" "$3" ;;
  plan-add-endpoint)
    need 4 "$@"; edit_plan_endpoints add "$@" ;;
  plan-remove-endpoint)
    need 4 "$@"; edit_plan_endpoints remove "$@" ;;
  *) usage >&2; exit 1 ;;
esac
cam_print
