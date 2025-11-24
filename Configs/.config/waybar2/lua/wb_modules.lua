return {
	backlight = function(builder)
		return {
			device = "intel_backlight",
			rotate = builder.variables.r_deg,
			format = "{icon} {percent}%",
			["format-icons"] = { "", "", "", "", "", "", "", "", "" },
			["tooltip-format"] = "{icon} {percent}% ",
			["on-scroll-up"] = "brightnesscontrol.sh i 1",
			["on-scroll-down"] = "brightnesscontrol.sh d 1",
			["min-length"] = 6,
		}
	end,
	battery = function(builder)
		return {
			states = { good = 95, warning = 30, critical = 20 },
			format = "{icon} {capacity}%",
			rotate = builder.variables.r_deg,
			["format-charging"] = " {capacity}%",
			["format-plugged"] = " {capacity}%",
			["format-alt"] = "{time} {icon}",
			["format-icons"] = { "󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹" },
		}
	end,
	bluetooth = function(builder)
		return {
			format = "",
			rotate = builder.variables.r_deg,
			["format-disabled"] = "",
			["format-connected"] = " {num_connections}",
			["format-connected-battery"] = "{icon} {num_connections}",
			["format-icons"] = { "󰥇", "󰤾", "󰤿", "󰥀", "󰥁", "󰥂", "󰥃", "󰥄", "󰥅", "󰥆", "󰥈" },
			["tooltip-format"] = "{controller_alias}\n{num_connections} connected",
			["tooltip-format-connected"] = "{controller_alias}\n{num_connections} connected\n\n{device_enumerate}",
			["tooltip-format-enumerate-connected"] = "{device_alias}",
			["tooltip-format-enumerate-connected-battery"] = "{device_alias}\t{icon} {device_battery_percentage}%",
		}
	end,
	["custom/cava"] = function(_)
		return {
			format = "{}",
			exec = "cava.sh waybar",
			["restart-interval"] = 1,
			["hide-empty"] = true,
		}
	end,
	["custom/cliphist"] = function(builder)
		return {
			format = "{}",
			rotate = builder.variables.r_deg,
			exec = "echo ; echo 󰅇 clipboard history",
			["on-click"] = "sleep 0.1 && cliphist.sh -c",
			["on-click-right"] = "sleep 0.1 && cliphist.sh -d",
			["on-click-middle"] = "sleep 0.1 && cliphist.sh -w",
			interval = 86400,
			tooltip = true,
		}
	end,
	clock = function(builder)
		return {
			format = "{:%I:%M %p}",
			rotate = builder.variables.r_deg,
			["format-alt"] = "{:%R 󰃭 %d·%m·%y}",
			["tooltip-format"] = "<span>{calendar}</span>",
			calendar = {
				mode = "month",
				["mode-mon-col"] = 3,
				["on-scroll"] = 1,
				["on-click-right"] = "mode",
				format = {
					months = "<span color='#ffead3'><b>{}</b></span>",
					weekdays = "<span color='#ffcc66'><b>{}</b></span>",
					today = "<span color='#ff6699'><b>{}</b></span>",
				},
			},
			actions = {
				["on-click-right"] = "mode",
				["on-click-forward"] = "tz_up",
				["on-click-backward"] = "tz_down",
				["on-scroll-up"] = "shift_up",
				["on-scroll-down"] = "shift_down",
			},
		}
	end,
	cpu = function(builder)
		return {
			interval = 10,
			format = "󰍛 {usage}%",
			rotate = builder.variables.r_deg,
			["format-alt"] = "{icon0}{icon1}{icon2}{icon3}",
			["format-icons"] = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" },
		}
	end,
	["custom/cpuinfo"] = function(builder)
		return {
			exec = "cpuinfo.sh",
			["return-type"] = "json",
			format = "{}",
			rotate = builder.variables.r_deg,
			interval = 5,
			tooltip = true,
			["max-length"] = 1000,
		}
	end,
	["custom/display"] = function(builder)
		return {
			format = "󱄄 ",
			rotate = builder.variables.r_deg,
			["tooltip-format"] = "󱄄  display settings",
			["on-click"] = "nwg-displays",
		}
	end,
	["custom/github_hyde"] = function(builder)
		return {
			format = " ",
			rotate = builder.variables.r_deg,
			["tooltip-format"] = "  See what's new in HyDE",
			["on-click"] = "xdg-open https://github.com/HyDE-Project/HyDE",
		}
	end,
	["custom/gpuinfo"] = function(builder)
		return {
			exec = "gpuinfo.sh",
			["return-type"] = "json",
			format = "{}",
			rotate = builder.variables.r_deg,
			interval = 5,
			tooltip = true,
			["max-length"] = 1000,
			["on-click"] = "gpuinfo.sh --toggle",
		}
	end,
	["custom/gpuinfo#nvidia"] = function(builder)
		return {
			exec = "gpuinfo.sh --use nvidia",
			["return-type"] = "json",
			format = "{}",
			rotate = builder.variables.r_deg,
			interval = 5,
			tooltip = true,
			["max-length"] = 1000,
		}
	end,
	["custom/gpuinfo#amd"] = function(builder)
		return {
			exec = "gpuinfo.sh --use amd",
			["return-type"] = "json",
			format = "{}",
			rotate = builder.variables.r_deg,
			interval = 5,
			tooltip = true,
			["max-length"] = 1000,
		}
	end,
	["custom/gpuinfo#intel"] = function(builder)
		return {
			exec = "gpuinfo.sh --use intel",
			["return-type"] = "json",
			format = "{}",
			rotate = builder.variables.r_deg,
			interval = 5,
			tooltip = true,
			["max-length"] = 1000,
		}
	end,
	["custom/hyprsunset"] = function(builder)
		return {
			["return-type"] = "json",
			format = "{icon}",
			["format-icons"] = { active = "", inactive = "" },
			exec = "hyprsunset.sh r q",
			rotate = builder.variables.r_deg,
			["on-click"] = "hyprsunset.sh t",
			["on-scroll-up"] = "hyprsunset.sh i",
			["on-scroll-down"] = "hyprsunset.sh d",
			interval = 1,
			tooltip = true,
			escape = true,
		}
	end,
	idle_inhibitor = function(builder)
		return {
			format = "{icon}",
			rotate = builder.variables.r_deg,
			["format-icons"] = { activated = "󰅶 ", deactivated = "󰛊 " },
			["tooltip-format-activated"] = "Caffeine Mode Active",
			["tooltip-format-deactivated"] = "Caffeine Mode Inactive",
		}
	end,
	["custom/keybindhint"] = function(builder)
		return {
			format = " ",
			["tooltip-format"] = " Keybinds",
			rotate = builder.variables.r_deg,
			["on-click"] = "keybinds_hint.sh",
		}
	end,
	["hyprland/language"] = function(builder)
		return {
			format = "{short} {variant}",
			rotate = builder.variables.r_deg,
			["on-click"] = "keyboardswitch.sh",
		}
	end,
	memory = function(builder)
		return {
			states = { c = 90, h = 60, m = 30 },
			interval = 5,
			format = "󰾆 {used}GB",
			rotate = builder.variables.r_deg,
			["format-m"] = "󰾅 {used}GB",
			["format-h"] = "󰓅 {used}GB",
			["format-c"] = " {used}GB",
			["format-alt"] = "󰾆 {percentage}%",
			["max-length"] = 10,
			tooltip = true,
			["tooltip-format"] = "󰾆 {percentage}%\n {used:0.1f}GB/{total:0.1f}GB",
		}
	end,
	disk = function(builder)
		return {
			states = { c = 90, h = 60, m = 30 },
			interval = 30,
			path = "/",
			rotate = builder.variables.r_deg,
			["format-m"] = "󰋊 {percentage_used}%",
			["format-h"] = "󰒋 {percentage_free}%",
			["format-c"] = "󰒌 {percentage_free}%",
			["format-alt"] = "󰋊 {used}%",
		}
	end,
	mpris = function(builder)
		return {
			format = "{player_icon} {dynamic}",
			rotate = builder.variables.r_deg,
			["format-paused"] = "{status_icon} <i>{dynamic}</i>",
			["player-icons"] = { default = "▶", mpv = "🎵" },
			["status-icons"] = { paused = "" },
			["max-length"] = 1000,
			interval = 1,
		}
	end,
	network = function(builder)
		return {
			tooltip = true,
			["format-wifi"] = " ",
			rotate = builder.variables.r_deg,
			["format-ethernet"] = "󰈀 ",
			["tooltip-format"] = "Network: <big><b>{essid}</b></big>\nSignal strength: <b>{signaldBm}dBm ({signalStrength}%)</b>\nFrequency: <b>{frequency}MHz</b>\nInterface: <b>{ifname}</b>\nIP: <b>{ipaddr}/{cidr}</b>\nGateway: <b>{gwaddr}</b>\nNetmask: <b>{netmask}</b>",
			["format-linked"] = "󰈀 {ifname} (No IP)",
			["format-disconnected"] = "󰖪 ",
			["tooltip-format-disconnected"] = "Disconnected",
			["format-alt"] = "<span foreground='#99ffdd'> {bandwidthDownBytes}</span> <span foreground='#ffcc66'> {bandwidthUpBytes}</span>",
			interval = 2,
		}
	end,
	["custom/notifications"] = function(builder)
		return {
			format = "{} {icon}",
			rotate = builder.variables.r_deg,
			["format-icons"] = {
				["email-notification"] = "<span foreground='white'><sup></sup></span>",
				["chat-notification"] = "󱋊<span foreground='white'><sup></sup></span>",
				["warning-notification"] = "󱨪<span foreground='yellow'><sup></sup></span>",
				["error-notification"] = "󱨪<span foreground='red'><sup></sup></span>",
				["network-notification"] = "󱂇<span foreground='white'><sup></sup></span>",
				["battery-notification"] = "󰁺<span foreground='white'><sup></sup></span>",
				["update-notification"] = "󰚰<span foreground='white'><sup></sup></span>",
				["music-notification"] = "󰝚<span foreground='white'><sup></sup></span>",
				["volume-notification"] = "󰕿<span foreground='white'><sup></sup></span>",
				notification = "<span foreground='white'><sup></sup></span>",
				dnd = "",
				none = "",
			},
			["return-type"] = "json",
			["exec-if"] = "which dunstctl",
			exec = "notifications.py",
			["on-scroll-down"] = "sleep 0.1 && dunstctl history-pop",
			["on-click"] = "dunstctl set-paused toggle",
			["on-click-middle"] = "dunstctl history-clear",
			["on-click-right"] = "dunstctl close-all",
			interval = 1,
			tooltip = true,
			escape = true,
		}
	end,
	["custom/power"] = function(builder)
		return {
			format = "{}",
			rotate = builder.variables.r_deg,
			exec = "echo ; echo  logout",
			["on-click"] = "logoutlaunch.sh 2",
			["on-click-right"] = "logoutlaunch.sh 1",
			interval = 86400,
			tooltip = true,
		}
	end,
	privacy = function(builder)
		return {
			["icon-size"] = builder.variables.i_priv,
			["icon-spacing"] = 5,
			["transition-duration"] = 250,
			modules = {
				{ type = "screenshare", tooltip = true, ["tooltip-icon-size"] = 24 },
				{ type = "audio-in", tooltip = true, ["tooltip-icon-size"] = 24 },
			},
		}
	end,
	pulseaudio = function(builder)
		return {
			format = "{icon} {volume}",
			rotate = builder.variables.r_deg,
			["format-muted"] = "婢",
			["on-click"] = "pavucontrol -t 3",
			["on-click-right"] = "volumecontrol.sh -s ''",
			["on-click-middle"] = "volumecontrol.sh -o m",
			["on-scroll-up"] = "volumecontrol.sh -o i",
			["on-scroll-down"] = "volumecontrol.sh -o d",
			["tooltip-format"] = "{icon} {desc} // {volume}%",
			["scroll-step"] = 5,
			["format-icons"] = {
				headphone = "",
				["hands-free"] = "",
				headset = "",
				phone = "",
				portable = "",
				car = "",
				default = { "", "", "" },
			},
		}
	end,
	["pulseaudio#microphone"] = function(builder)
		return {
			format = "{format_source}",
			rotate = builder.variables.r_deg,
			["format-source"] = "",
			["format-source-muted"] = "",
			["on-click"] = "pavucontrol -t 4",
			["on-click-middle"] = "volumecontrol.sh -i m",
			["on-scroll-up"] = "volumecontrol.sh -i i",
			["on-scroll-down"] = "volumecontrol.sh -i d",
			["tooltip-format"] = "{format_source} {source_desc} // {source_volume}%",
			["scroll-step"] = 5,
		}
	end,
	["custom/sensorsinfo"] = function(builder)
		return {
			exec = "sensorsinfo.py",
			["return-type"] = "json",
			format = "{}",
			rotate = builder.variables.r_deg,
			interval = 5,
			tooltip = true,
			["max-length"] = 1000,
			["on-click"] = "sensorsinfo.py --next",
			signal = 19,
		}
	end,
	["custom/spotify"] = function(builder)
		return {
			exec = "mediaplayer.py --player spotify",
			format = "{}",
			rotate = builder.variables.r_deg,
			["return-type"] = "json",
			["on-click"] = "playerctl play-pause --player spotify",
			["on-click-right"] = "playerctl next --player spotify",
			["on-click-middle"] = "playerctl previous --player spotify",
			["on-scroll-up"] = "volumecontrol.sh -p spotify i",
			["on-scroll-down"] = "volumecontrol.sh -p spotify d",
			tooltip = true,
		}
	end,
	["wlr/taskbar"] = function(builder)
		return {
			["all-outputs"] = true,
			["active-first"] = true,
			markup = true,
			format = "{icon}",
			rotate = builder.variables.r_deg,
			["icon-size"] = builder.variables.i_task,
			["icon-theme"] = builder.variables.i_theme,
			spacing = 0,
			["tooltip-format"] = "{title}{app_id}",
			["on-click"] = "activate",
			["on-click-right"] = "fullscreen",
			["on-click-middle"] = "close",
			["ignore-list"] = { "" },
			["app_ids-mapping"] = {
				firefoxdeveloperedition = "firefox-developer-edition",
				firefoxnightly = "firefox-nightly",
				["Spotify Free"] = "Spotify",
			},
			rewrite = {
				["Firefox Web Browser"] = "Firefox",
				["Foot Server"] = "Terminal",
				["Spotify Free"] = "Spotify",
				["org.kde.dolphin"] = "dolphin",
				["libreoffice-writer"] = "writer",
			},
		}
	end,
	["wlr/taskbar#windows"] = function(builder)
		return {
			format = "{icon}{app_id}",
			rotate = builder.variables.r_deg,
			["icon-size"] = builder.variables.i_task,
			["icon-theme"] = builder.variables.i_theme,
			spacing = 0,
			["tooltip-format"] = "{title}",
			["on-click"] = "activate",
			["on-click-middle"] = "close",
			["ignore-list"] = { "Alacritty" },
			["app_ids-mapping"] = {
				firefoxdeveloperedition = "firefox-developer-edition",
				["jetbrains-datagrip"] = "DataGrip",
			},
		}
	end,
	["custom/theme"] = function(builder)
		return {
			format = "{}",
			rotate = builder.variables.r_deg,
			exec = "echo ; echo 󰟡 switch theme",
			["on-click"] = "themeswitch.sh -n",
			["on-click-right"] = "themeswitch.sh -p",
			["on-click-middle"] = "sleep 0.1 && themeselect.sh",
			interval = 86400,
			tooltip = true,
		}
	end,
	tray = function(builder)
		return {
			["icon-size"] = builder.variables.i_size,
			rotate = builder.variables.r_deg,
			spacing = 5,
		}
	end,
	["custom/updates"] = function(builder)
		return {
			exec = "systemupdate.sh",
			["return-type"] = "json",
			format = "{}",
			rotate = builder.variables.r_deg,
			["on-click"] = "hyprctl dispatch exec 'systemupdate.sh up'",
			interval = 86400,
			tooltip = true,
			signal = 20,
		}
	end,
	["custom/wallchange"] = function(builder)
		return {
			format = "{}",
			rotate = builder.variables.r_deg,
			exec = "echo ; echo 󰆊 switch wallpaper",
			["on-click"] = "swwwallpaper.sh -n",
			["on-click-right"] = "swwwallpaper.sh -p",
			["on-click-middle"] = "sleep 0.1 && swwwallselect.sh",
			interval = 86400,
			tooltip = true,
		}
	end,
	["custom/wbar"] = function(builder)
		return {
			format = "{}",
			rotate = builder.variables.r_deg,
			exec = "echo ; echo  switch bar //  dock",
			["on-click"] = "$XDG_CONFIG_HOME/waybar/waybar.lua next",
			["on-click-right"] = "$XDG_CONFIG_HOME/waybar/waybar.lua prev",
			["on-click-middle"] = "sleep 0.1 && quickapps.sh zen-browser kitty thunar nvim btop",
			interval = 86400,
			tooltip = true,
		}
	end,
	["custom/weather"] = function(_)
		return {
			exec = "weather.py",
			tooltip = true,
			format = "{}",
			interval = 30,
			["return-type"] = "json",
		}
	end,
	["custom/niflveil"] = function(_)
		return {
			format = "{}",
			exec = "niflveil show",
			["on-click"] = "niflveil restore-last",
			["return-type"] = "json",
			interval = "once",
			signal = 8,
		}
	end,
	["hyprland/window"] = function(builder)
		return {
			format = "  {}",
			rotate = builder.variables.r_deg,
			["separate-outputs"] = true,
			rewrite = {
				["${USER}@${set_sysname}:(.*)"] = "$1 ",
				["(.*) — Mozilla Firefox"] = "$1 󰈹",
				["(.*)Mozilla Firefox"] = "Firefox 󰈹",
				["(.*) - Visual Studio Code"] = "$1 󰨞",
				["(.*)Visual Studio Code"] = "Code 󰨞",
				["(.*) - Code - OSS"] = "$1 󰨞",
				["(.*)Code - OSS"] = "Code 󰨞",
				["(.*) — Dolphin"] = "$1 󰉋",
				["(.*)Spotify"] = "Spotify 󰓇",
				["(.*)Steam"] = "Steam 󰓓",
				["(.*) - Discord"] = "$1  ",
				["(.*)Netflix"] = "Netflix 󰝆 ",
				["(.*) — Google chrome"] = "$1  ",
				["(.*)Google chrome"] = "Google chrome  ",
				["(.*) — Github"] = "$1  ",
				["(.*)Github"] = "Github ",
				["(.*)Spotify Free"] = "Spotify 󰓇",
				["(.*)Spotify Premiun"] = "Spotify 󰓇",
			},
			["max-length"] = 50,
		}
	end,
	["hyprland/workspaces"] = function(builder)
		return {
			["disable-scroll"] = true,
			rotate = builder.variables.r_deg,
			["all-outputs"] = true,
			["active-only"] = false,
			["on-click"] = "activate",
			["on-scroll-up"] = "hyprctl dispatch workspace -1",
			["on-scroll-down"] = "hyprctl dispatch workspace +1",
			["persistent-workspaces"] = {},
		}
	end,
	["custom/l_end"] = function(_)
		return { format = " ", interval = "once", tooltip = false }
	end,
	["custom/r_end"] = function()
		return { format = " ", interval = "once", tooltip = false }
	end,
	["custom/sl_end"] = function()
		return { format = " ", interval = "once", tooltip = false }
	end,
	["custom/sr_end"] = function()
		return { format = " ", interval = "once", tooltip = false }
	end,
	["custom/rl_end"] = function()
		return { format = " ", interval = "once", tooltip = false }
	end,
	["custom/rr_end"] = function()
		return { format = " ", interval = "once", tooltip = false }
	end,
	["custom/padd"] = function()
		return { format = "  ", interval = "once", tooltip = false }
	end,
}
