#!/bin/bash
set -euo pipefail

# [[ "${HYDE_SHELL_INIT}" -ne 1 ]] && eval "$(hyde-shell init)"

# Define the terminal's class name or identifier for the dropdown terminal
TERMINAL_CLASS="drop_term"
TERMINAL=$1

# Function to toggle the dropdown terminal
toggle_dropdown_terminal() {
  # Check if the terminal is already open
  drop_term=$(hyprctl clients -j | jq -r --arg class "$TERMINAL_CLASS" '.[] | select(.class == $class)')
  local win_id
  win_id=$(echo "$drop_term" | jq -r '.workspace.id')
  echo "Dropdown terminal ID: $win_id"
  if [ -n "$drop_term" ]; then
    # If it is open, close it
    echo "Closing dropdown terminal..."
    hyprctl dispatch closewindow class:$TERMINAL_CLASS
  else
    # If it is not open, start it
    if [ -n "$TERMINAL" ]; then
      echo "Opening dropdown terminal..."
      eval "$TERMINAL --class $TERMINAL_CLASS"
    fi
  fi
}

toggle_dropdown_terminal
