# shellcheck shell=bash
# Terminal output. Without a terminal everything degrades to plain lines, so
# unattended runs produce a readable log.

# gum draws on stderr, and stdout is often captured.
ui_interactive() { [ -t 0 ] && [ -t 2 ]; }

# ui_header TITLE SUBTITLE CURRENT LABEL...
ui_header() {
  local title=$1 subtitle=$2 current=$3 i
  shift 3
  if ! ui_interactive; then
    printf '\n==> %s  (%s)\n' "${!current}" "$subtitle"
    return
  fi
  clear
  gum style --border double --border-foreground 6 --padding "0 3" --margin "1 0" \
    --bold "$title" "$(gum style --foreground 8 "$subtitle")"
  for ((i = 1; i <= $#; i++)); do
    if [ "$i" -lt "$current" ]; then
      gum style --foreground 2 "  [x] ${!i}"
    elif [ "$i" -eq "$current" ]; then
      gum style --foreground 6 --bold "  [>] ${!i}"
    else
      gum style --foreground 8 "  [ ] ${!i}"
    fi
  done
  echo
}

ui_info() { gum style --foreground 8 "$*"; }

# Writes to stderr so a failure inside $(...) never ends up in the value.
ui_die() {
  {
    echo
    gum style --border normal --border-foreground 1 --foreground 1 --padding "0 1" \
      "ERROR" "$1" "" "Log: $LOG"
    ui_interactive || tail -n 40 "$LOG"
  } >&2
  exit 1
}

# ui_box COLOR TITLE LINE...
ui_box() {
  local color=$1 title=$2
  shift 2
  gum style --border normal --border-foreground "$color" --padding "0 1" \
    "$(gum style --bold "$title")" "" "$@"
}

# Runs a command or function in the background with its output in $LOG and
# shows a spinner until it exits.
ui_spin() {
  local title=$1 pid
  shift
  echo "==> $title" >>"$LOG"
  "$@" >>"$LOG" 2>&1 &
  pid=$!
  if ui_interactive; then
    gum spin --spinner line --title "$title" -- tail --pid="$pid" -f /dev/null
  else
    echo "$title"
  fi
  wait "$pid" || ui_die "$title failed"
}

# Like ui_spin, but for nix builds, which get nix-output-monitor on a terminal.
ui_nix_build() {
  if ui_interactive; then
    nix build --log-format internal-json -v "$@" |& nom --json
  else
    nix build -L "$@"
  fi
}

# ui_choose HEADER OPTION...
ui_choose() {
  ui_interactive || ui_die "$1 (needs a terminal, or pass the choice as a flag)"
  gum choose --header "$@"
}

ui_confirm() { ui_interactive && gum confirm "$@"; }

# ui_confirm_word WORD PROMPT
ui_confirm_word() {
  local answer
  answer=$(gum input --placeholder "$2")
  [ "$answer" = "$1" ]
}
