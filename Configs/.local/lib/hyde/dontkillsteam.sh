if [[ $(hyprctl activewindow -j | jq -r ".class") == "Steam" ]]; then
    # if xdotool is installed, use it to minimize the window instead of killing it
    if command -v xdotool &>/dev/null; then
        xdotool windowunmap "$(xdotool getactivewindow)"
    elif command -v niflveil.sh &>/dev/null; then
        niflveil.sh minimize
    fi
else
    hyprctl dispatch killactive
fi
