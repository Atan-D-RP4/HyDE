if [[ $(hyprctl activewindow -j | jq -r ".class") == "Steam" ]]; then
    xdotool windowunmap $(xdotool getactivewindow)
else
    # check if active window is fullscreen
    IS_FULLSCREEN=$(hyprctl activewindow -j | jq -r ".fullscreen")
    hyprctl dispatch killactive ""
    # If $IS_FULLSCREEN is not 0 or "false", toggle fullscreen
    if [[ "$IS_FULLSCREEN" != 0 ]]; then
        hyprctl dispatch fullscreen
    fi
fi
