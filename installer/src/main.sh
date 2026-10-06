# shellcheck shell=bash
# The OPT_*, PLAN and STARTED globals are read by the step functions.
# shellcheck disable=SC2034

usage() {
  cat <<EOF
Usage: carbos-install [options] [host]

Installs carbos. Without a host it picks the one whose disk is attached.

Options:
  --dry-run      show the plan and stop. Changes nothing and needs no root.
  --mode MODE    keep or wipe the existing data instead of asking.
  --unattended   never prompt and never reboot. Needs --mode.
  -h, --help     show this help.
EOF
}

ARGS=("$@")
OPT_DRY_RUN=""
OPT_UNATTENDED=""
OPT_MODE=""
OPT_HOST=""
while [ $# -gt 0 ]; do
  case $1 in
  --dry-run) OPT_DRY_RUN=1 ;;
  --unattended) OPT_UNATTENDED=1 ;;
  --mode)
    OPT_MODE=${2:-}
    shift
    ;;
  -h | --help)
    usage
    exit
    ;;
  -*)
    usage >&2
    exit 2
    ;;
  *) OPT_HOST=$1 ;;
  esac
  shift
done
case $OPT_MODE in
"" | keep | wipe) ;;
*)
  echo "--mode must be keep or wipe" >&2
  exit 2
  ;;
esac
if [ -n "$OPT_UNATTENDED" ] && [ -z "$OPT_MODE" ]; then
  echo "--unattended needs --mode" >&2
  exit 2
fi

if [ -z "$OPT_DRY_RUN" ] && [ "$(id -u)" -ne 0 ]; then
  exec sudo "$0" "${ARGS[@]}"
fi

STEPS=(host network plan verify partition install finish)
DRY_RUN_STEPS=(host plan)
declare -A LABELS=(
  [host]=Host
  [network]=Network
  [plan]="Disk plan"
  [verify]="Verify store"
  [partition]=Partition
  [install]=Install
  [finish]=Done
)

declare -A PLAN=()
LOG="/tmp/carbos-install-$(id -un).log"
STARTED=$SECONDS
: >"$LOG"

subtitle() {
  printf 'rev %s' "$(bundle_get .rev)"
  [ -z "${PLAN[host]:-}" ] || printf '  %s on %s' "${PLAN[host]}" "${PLAN[disk]}"
}

run_steps() {
  local steps=("$@") labels=() step i
  for step in "${steps[@]}"; do
    labels+=("${LABELS[$step]}")
  done
  for i in "${!steps[@]}"; do
    ui_header "carbos installer" "$(subtitle)" $((i + 1)) "${labels[@]}"
    "step_${steps[$i]}"
  done
}

if [ -n "$OPT_DRY_RUN" ]; then
  run_steps "${DRY_RUN_STEPS[@]}"
  ui_info "Dry run, nothing was changed."
else
  run_steps "${STEPS[@]}"
fi
