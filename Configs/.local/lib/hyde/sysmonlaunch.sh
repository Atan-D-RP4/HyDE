#!/usr/bin/env bash

scrDir="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${scrDir}/globalcontrol.sh"

show_help() {
  cat <<HELP
Usage: $(basename "$0") --[option]
    -h, --help      Display this help and exit
    -e, --execute   Explicit command to execute

Config: ~/.config/hyde/config.toml

    [sysmonitor]
    execute = "btop"                    # Default command to execute // accepts executable or app.desktop
    commands = ["btop", "htop", "top"]  # Fallback command options
    terminal = "kitty"                  # Explicit terminal // uses \$TERMINAL if available


This script launches the system monitor application.
    It will launch the first available system monitor
    application from the list of 'commands' provided.
    Re-running toggles it off.

HELP
}

case $1 in
-h | --help)
  show_help
  exit 0
  ;;
-e | --execute)
  shift
  SYSMONITOR_EXECUTE=$1
  ;;
-*)
  echo "Unknown option: $1" >&2
  exit 1
  ;;
esac

pidFile="$XDG_RUNTIME_DIR/hyde/sysmonlaunch.pid"
mkdir -p "$(dirname "$pidFile")"

# ------------------------------------------------------------------------------
# Toggle OFF: kill stored PGID
# ------------------------------------------------------------------------------

if [ -f "$pidFile" ]; then
  IFS=":::" read -r saved_pgid saved_cmd <"$pidFile"

  if [ -n "$saved_pgid" ] && ps -o pid= -g "$saved_pgid" | grep -q .; then
    # Kill the entire session/process group
    kill -- -"$saved_pgid" 2>/dev/null || true
    sleep 0.05
    if ps -o pid= -g "$saved_pgid" | grep -q .; then
      kill -9 -- -"$saved_pgid" 2>/dev/null || true
    fi

    # Try flatpak kill for flatpak apps (harmless otherwise)
    pkg_installed flatpak && [[ -n "$saved_cmd" ]] && flatpak kill "$saved_cmd" 2>/dev/null || true

    rm -f "$pidFile"
    exit 0
  fi

  # stale pid file
  rm -f "$pidFile"
fi

# ------------------------------------------------------------------------------
# Helpers: determine how to launch a command in a given terminal
# ------------------------------------------------------------------------------

# Try to run a command in a terminal binary using known invocation patterns.
# Returns: prints the PID of the launched process to stdout (and exits 0) or exits non-zero.
_launch_in_terminal() {
  local term_bin="$1"
  local the_cmd="$2"

  # prefer absolute binary if provided as a path
  if [ -x "$term_bin" ]; then
    term_bin_path="$term_bin"
  else
    term_bin_path="$(command -v "$term_bin" 2>/dev/null || true)"
  fi

  if [ -z "$term_bin_path" ]; then
    return 1
  fi

  # detect base name
  local base
  base="$(basename "$term_bin_path")"

  # build argv array differently depending on terminal
  local -a argv

  case "$base" in
  gnome-terminal | gnome-terminal-server)
    # gnome-terminal needs "--" then a shell command
    argv=("$term_bin_path" -- bash -lc "$the_cmd")
    ;;
  tilix)
    argv=("$term_bin_path" -e bash -lc "$the_cmd")
    ;;
  konsole)
    argv=("$term_bin_path" -e bash -lc "$the_cmd")
    ;;
  xfce4-terminal)
    argv=("$term_bin_path" -e bash -lc "$the_cmd")
    ;;
  alacritty | kitty | xterm | urxvt | rxvt | st | qterminal | foot)
    # most lightweight terminals accept -e <command>
    argv=("$term_bin_path" -e "$the_cmd")
    ;;
  *)
    # generic attempt: try -e, then -- bash -lc
    argv=("$term_bin_path" -e "$the_cmd")
    # test whether it works by attempting to run; we'll fall back later if it fails
    ;;
  esac

  # Launch the constructed argv in a new session so we control PGID deterministically
  setsid "${argv[@]}" >/dev/null 2>&1 &
  local launcher_pid=$!

  # Give it a short moment
  sleep 0.08

  # verify process exists
  if [ -n "$launcher_pid" ] && ps -p "$launcher_pid" >/dev/null 2>&1; then
    printf '%s\n' "$launcher_pid"
    return 0
  fi

  # last resort: try invoking via hyde-shell app (legacy behavior)
  if command -v hyde-shell >/dev/null 2>&1; then
    setsid hyde-shell app "$term_bin" "$the_cmd" >/dev/null 2>&1 &
    launcher_pid=$!
    sleep 0.08
    if [ -n "$launcher_pid" ] && ps -p "$launcher_pid" >/dev/null 2>&1; then
      printf '%s\n' "$launcher_pid"
      return 0
    fi
  fi

  return 1
}

# ------------------------------------------------------------------------------
# Toggle ON: find an available monitor and launch it in a controlled session
# ------------------------------------------------------------------------------

pkgChk=("io.missioncenter.MissionCenter" "htop" "btop" "top")                     # Array of commands to check
pkgChk+=("${SYSMONITOR_COMMANDS[@]}")                                             # Add the user defined array commands
[ -n "${SYSMONITOR_EXECUTE}" ] && pkgChk=("${SYSMONITOR_EXECUTE}" "${pkgChk[@]}") # Add the user defined executable

for cmd in "${pkgChk[@]}"; do
  if ! pkg_installed "$cmd"; then
    continue
  fi

  # Get terminal from config, environment, or default
  term=$(grep -E '^\s*terminal' "$HOME/.config/hypr/keybindings.conf" 2>/dev/null | cut -d '=' -f2 | xargs) # search the config
  term=${TERMINAL:-$term}                                                                                   # Use env var
  term=${SYSMONITOR_TERMINAL:-$term}                                                                        # Use config override
  term=${term:-"kitty"}                                                                                     # Final fallback

  # Try to launch using the terminal binary with known patterns
  launcher_pid=""
  launcher_pid="$(_launch_in_terminal "$term" "$cmd" 2>/dev/null || true)"

  # If launch failed, try to resolve term (maybe it's a desktop name) and try again with common terminals
  if [ -z "$launcher_pid" ]; then
    # try common terminal binaries in PATH as fallbacks
    for candidate in kitty alacritty xterm gnome-terminal konsole alacritty xfce4-terminal qterminal st; do
      if command -v "$candidate" >/dev/null 2>&1; then
        launcher_pid="$(_launch_in_terminal "$candidate" "$cmd" 2>/dev/null || true)"
        if [ -n "$launcher_pid" ]; then
          term="$candidate"
          break
        fi
      fi
    done
  fi

  # If still empty, try desktop launch fallback
  if [ -z "$launcher_pid" ] && gtk-launch "$cmd" 2>/dev/null; then
    pid=$(pgrep -n -x "$cmd" 2>/dev/null || true)
    if [ -n "$pid" ]; then
      pgid=$(ps -o pgid= -p "$pid" | tr -d ' ' || true)
      if [ -n "$pgid" ]; then
        echo "${pgid}:::${cmd}" >"$pidFile"
        exit 0
      fi
    fi
  fi

  # If we have a launcher_pid, that PID is the leader of the new session (PGID)
  if [ -n "$launcher_pid" ]; then
    # The setsid'd process is its own PGID; store that
    echo "${launcher_pid}:::${cmd}" >"$pidFile"
    exit 0
  fi
done

# If we get here, nothing launched
exit 1

This script is really slow. Since we treat all terminals the same, can we just skip any checking for them and just use xdg-terminal-exec.
