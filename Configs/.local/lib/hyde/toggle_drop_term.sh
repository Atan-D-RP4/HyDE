#!/bin/bash

# [[ "${HYDE_SHELL_INIT}" -ne 1 ]] && eval "$(hyde-shell init)"

# Define the terminal's class name or identifier for the dropdown terminal
TERMINAL_CLASS="drop_term"
TERMINAL=$1

# Check if the terminal is already running
if pgrep -f "$TERMINAL_CLASS" >/dev/null; then
  # If running, kill the process
  pkill -f "$TERMINAL_CLASS"
else
  # If not running, launch the dropdown terminal
  cmd=($TERMINAL "--class" "drop_term")
  "${cmd[@]}"
fi
