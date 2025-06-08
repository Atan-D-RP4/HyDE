#!/usr/bin/env bash

scrDir="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${scrDir}/globalcontrol.sh"

show_help() {
  cat <<HELP
Usage: $(basename "$0") --[option]
    -h, --help  Display this help and exit
    -e, --execute   Explicit command to execute

Config: ~/.config/hyde/config.toml

    [sysmonitor]
    execute = "btop"                    # Default command to execute // accepts executable or app.desktop
    commands = ["btop", "htop", "top"]  # Fallback command options
    terminal = "kitty"                  # Explicit terminal // uses \$TERMINAL if available


This script launches the system monitor application.
    It will launch the first available system monitor
    application from the list of 'commands' provided.


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

pidFile="$HYDE_RUNTIME_DIR/sysmonlaunch.pid"

# TODO: As there is no proper protocol at terminals, we need to find a way to kill the processes
# * This enables toggling the sysmonitor on and off
if [ -f "$pidFile" ]; then
  while IFS= read -r line; do
    pid=$(awk -F ':::' '{print $1}' <<<"$line")
    cmd=$(awk -F ':::' '{print $2}' <<<"$line")

    if [ -d "/proc/${pid}" ]; then
      # Handle special kitty case
      if [[ "$cmd" == kitty-* ]]; then
        # Extract the actual command name from kitty-<command>
        actual_cmd="${cmd#kitty-}"
        # Kill the monitor process directly
        pkill -f "$actual_cmd"
        # Also try to kill any child processes of the kitty instance
        pkill -P "$pid"
      else
        # Standard process killing
        pkill -P "$pid"
        # Try flatpak kill for flatpak apps
        pkg_installed flatpak && flatpak kill "$cmd" 2>/dev/null
        # Also kill the process itself if it's still running
        kill "$pid" 2>/dev/null
      fi
      rm "$pidFile"
      exit 0
    fi
  done <"$pidFile"
  rm "$pidFile"
fi

pkgChk=("io.missioncenter.MissionCenter" "htop" "btop" "top")                     # Array of commands to check
pkgChk+=("${SYSMONITOR_COMMANDS[@]}")                                             # Add the user defined array commands
[ -n "${SYSMONITOR_EXECUTE}" ] && pkgChk=("${SYSMONITOR_EXECUTE}" "${pkgChk[@]}") # Add the user defined executable

for sysMon in "${!pkgChk[@]}"; do
  # If that fails, try launching in terminal
  if pkg_installed "${pkgChk[sysMon]}"; then
    # Get terminal from config, environment, or default
    term=$(grep -E '^\s*'"terminal" "$HOME/.config/hypr/keybindings.conf" 2>/dev/null | cut -d '=' -f2 | xargs) # search the config
    term=${TERMINAL:-$term}                                                                      # Use env var
    term=${SYSMONITOR_TERMINAL:-$term}                                                          # Use config override
    term=${term:-"kitty"}                                                                       # Final fallback

    # Launch with appropriate terminal command
    case "$term" in
      *kitty*)
        # Use kitty with single-instance flag
        if kitty --single-instance "${pkgChk[sysMon]}" &; then
          # Wait a moment for the process to start, then find the actual monitor process
          sleep 0.5
          pid=$(pgrep -n -f "${pkgChk[sysMon]}")
          if [ -n "$pid" ]; then
            echo "${pid}:::${pkgChk[sysMon]}" >"$pidFile" # Save the monitor process PID
          else
            # Fallback: save kitty PID with special marker
            echo "$!:::kitty-${pkgChk[sysMon]}" >"$pidFile"
          fi
          disown
          break
        fi
        ;;
      *)
        # Use standard terminal execution for other terminals
        if "$term" "${pkgChk[sysMon]}" &; then
          pid=$!
          echo "${pid}:::${pkgChk[sysMon]}" >"$pidFile" # Save the PID to the file
          disown
          break
        fi
        ;;
    esac
  fi
  # First try to launch as desktop application
  if gtk-launch "${pkgChk[sysMon]}" 2>/dev/null; then
    pid=$(pgrep -n -f "${pkgChk[sysMon]}")
    echo "${pid}:::${pkgChk[sysMon]}" >"$pidFile" # Save the PID to the file
    break
  fi
done
