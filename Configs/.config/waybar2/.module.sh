link \
  "$XDG_CONFIG_HOME/waybar/config.jsonc" \
  "$XDG_CONFIG_HOME/waybar/waybar.lua" \
  "$XDG_CONFIG_HOME/waybar/style.css" ./style.css \
  "$XDG_CONFIG_HOME/waybar/theme.css" ./theme.css

link-to "$XDG_CONFIG_HOME/waybar/lua/" ./lua/*

packages \
  pacman:waybar,lua51,lua51-dkjson \
  paru:waybar,lua51,lua51-dkjson

eval "$XDG_CONFIG_HOME/waybar/waybar.lua"
