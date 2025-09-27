#!/bin/bash

# Port of NiflVeil - A window minimizer for Hyprland
# Original Project repository: https://github.com/Mauitron/NiflVeil.git

# Constants
CACHE_DIR="/tmp/minimize-state"
CACHE_FILE="/tmp/minimize-state/windows.json"
PREVIEW_DIR="/tmp/window-previews"

# Icon mappings
declare -A ICONS=(
	["Zen"]=""
	["Alacritty"]=""
	["discord"]="󰙯"
	["Steam"]=""
	["chromium"]=""
	["code"]="󰨞"
	["spotify"]=""
	["nvim"]="󰈙"
	["kitty"]="󰌌"
	["TelegramDesktop"]="󰖲"
	["Slack"]="󰖲"
	["GIMP"]="󰖲"
	["Inkscape"]="󰖲"
	["OBS Studio"]="󰖲"
	["VLC media player"]="󰖲"
	["mpv"]="󰖲"
	["Krita"]="󰖲"
	["Blender"]="󰖲"
	["VirtualBox"]="󰖲"
	["LibreOffice"]="󰖲"
	["default"]="󰖲"
)

# Check if running in HyDE environment
HYDE_MODE=false
if command -v hyde-shell >/dev/null 2>&1; then
	if source "$(command -v hyde-shell)" 2>/dev/null; then
		HYDE_MODE=true
	fi
fi

# Function to setup Rofi configuration (HyDE integration)
setup_rofi_config() {
	[[ "$HYDE_MODE" == false ]] && return

	# Font configuration
	local font_scale="${ROFI_MINIMIZER_SCALE:-${ROFI_SCALE:-10}}"
	[[ "${font_scale}" =~ ^[0-9]+$ ]] || font_scale=10
	font_name="${font_name:-JetBrainsMono Nerd Font}"
	font_override="* {font: \"${font_name} ${font_scale}\";}"

	# Border settings
	local hypr_border wind_border elem_border
	if command -v hyprctl >/dev/null 2>&1; then
		hypr_border=$(hyprctl -j getoption decoration:rounding 2>/dev/null | jq -r '.int' 2>/dev/null || echo "5")
		local hypr_width=$(hyprctl -j getoption general:border_size 2>/dev/null | jq -r '.int' 2>/dev/null || echo "2")
	else
		hypr_border=5
		hypr_width=2
	fi

	wind_border=$((hypr_border * 3 / 2))
	elem_border=$((hypr_border == 0 ? 5 : hypr_border))

	# Position
	if command -v get_rofi_pos >/dev/null 2>&1; then
		rofi_position=$(get_rofi_pos 2>/dev/null || echo "")
	else
		rofi_position=""
	fi

	r_override="window{border:${hypr_width}px;border-radius:${wind_border}px;}wallbox{border-radius:${elem_border}px;} element{border-radius:${elem_border}px;}"
}

# Function to get app icon
get_app_icon() {
	local class_name="$1"
	local lower_class="${class_name,,}"

	for icon_name in "${!ICONS[@]}"; do
		if [[ "$lower_class" == *"${icon_name,,}"* ]]; then
			echo "${ICONS[$icon_name]}"
			return
		fi
	done

	echo "${ICONS[default]}"
}

# Function to capture window preview
capture_window_preview() {
	local window_id="$1"
	local geometry="$2"
	local preview_path="${PREVIEW_DIR}/${window_id}.png"
	local thumb_path="${PREVIEW_DIR}/${window_id}.thumb.png"

	# Create preview directory if it doesn't exist
	mkdir -p "$PREVIEW_DIR"

	# Capture screenshot
	if ! grim -g "$geometry" "$preview_path" 2>/dev/null; then
		return 1
	fi

	# Create thumbnail
	if ! convert "$preview_path" -resize "200x150^" -gravity center -extent "200x150" "$thumb_path" 2>/dev/null; then
		rm -f "$preview_path"
		return 1
	fi

	# Remove original preview
	rm -f "$preview_path"

	echo "$thumb_path"
}

# Function to escape JSON strings
escape_json() {
	local str="$1"
	echo "$str" | sed 's/"/\\"/g'
}

# Function to create JSON output
create_json_output() {
	local windows=("$@")
	local json_array="["
	local first=true

	for window in "${windows[@]}"; do
		if [[ "$first" == true ]]; then
			first=false
		else
			json_array+=","
		fi
		json_array+="$window"
	done

	json_array+="]"
	echo "$json_array"
}

# Function to parse window info from hyprctl JSON
parse_window_info() {
	local info="$1"
	local key="$2"

	echo "$info" | jq -r ".${key} // empty" 2>/dev/null || echo ""
}

# Function to signal waybar
signal_waybar() {
	pkill -RTMIN+8 waybar 2>/dev/null || true
}

# Function to restore specific window
restore_specific_window() {
	local window_id="$1"

	echo "Attempting to restore window: $window_id" >&2

	# Get current workspace
	local workspace_info
	workspace_info=$(hyprctl activeworkspace -j 2>/dev/null)
	if [[ $? -ne 0 ]]; then
		echo "Failed to get active workspace" >&2
		return 1
	fi

	echo "Workspace info: $workspace_info" >&2
	local current_ws
	current_ws=$(echo "$workspace_info" | jq -r '.id // 1' 2>/dev/null)
	[[ -z "$current_ws" || "$current_ws" == "null" ]] && current_ws=1

	# Move window from special workspace to current workspace
	local move_result
	move_result=$(hyprctl dispatch movetoworkspace "${current_ws},address:${window_id}" 2>&1)
	echo "Move from special workspace result: $move_result" >&2

	# Focus the window
	local focus_result
	focus_result=$(hyprctl dispatch focuswindow "address:${window_id}" 2>&1)
	echo "Focus command result: $focus_result" >&2

	# Get active window info
	local window_info
	window_info=$(hyprctl activewindow -j 2>/dev/null)
	if [[ $? -ne 0 ]]; then
		echo "Failed to get active window info" >&2
		return 1
	fi

	local pid
	pid=$(parse_window_info "$window_info" "pid")
	if [[ -z "$pid" || ! "$pid" =~ ^[0-9]+$ ]]; then
		echo "No valid PID found for the window" >&2
		return 1
	fi

	# Send SIGCONT to the process
	if signal_process_tree "$pid" "CONT"; then
		# if kill -s CONT "$pid" 2>/dev/null; then
		echo "Process with PID $pid resumed successfully" >&2
	else
		echo "Failed to resume process with PID $pid" >&2
		return 1
	fi
	# Or
	# local sigcont_result
	# sigcont_result=$(hyprctl dispatch signalwindow 18 "address:${window_id}" 2>&1)

	# Update cache file - remove the restored window
	if [[ -f "$CACHE_FILE" ]]; then
		local temp_file=$(mktemp)
		local updated_windows=()

		# Read existing windows and filter out the restored one
		while IFS= read -r line; do
			if [[ -n "$line" ]]; then
				local addr
				addr=$(echo "$line" | jq -r '.address // empty' 2>/dev/null)
				if [[ "$addr" != "$window_id" ]]; then
					updated_windows+=("$line")
				fi
			fi
		done < <(jq -c '.[]' "$CACHE_FILE" 2>/dev/null || echo "")

		# Write updated cache
		create_json_output "${updated_windows[@]}" >"$CACHE_FILE"
		rm -f "$temp_file"
	fi

	signal_waybar
}

# Function to restore all windows
restore_all_windows() {
	[[ ! -f "$CACHE_FILE" ]] && return

	local windows
	windows=$(jq -r '.[].address' "$CACHE_FILE" 2>/dev/null)

	while IFS= read -r window_id; do
		[[ -n "$window_id" && "$window_id" != "null" ]] && restore_specific_window "$window_id"
	done <<<"$windows"
}

# Function to show restore menu using rofi
show_restore_menu() {
	echo "Starting restore menu..." >&2

	if [[ ! -f "$CACHE_FILE" ]]; then
		echo "Cache file does not exist" >&2
		return 1
	fi

	local content windows_count
	content=$(cat "$CACHE_FILE" 2>/dev/null)
	windows_count=$(echo "$content" | jq '. | length' 2>/dev/null || echo "0")

	echo "Parsed $windows_count windows" >&2

	if [[ "$windows_count" -eq 0 ]]; then
		echo "No minimized windows" >&2
		return 1
	fi

	# Setup rofi configuration
	setup_rofi_config

	# Create menu options
	local menu_options=""
	local window_addresses=()

	# Add restore all option
	menu_options+="󰶼 Restore All Windows\n"
	window_addresses+=("RESTORE_ALL")

	# Add individual windows
	while IFS= read -r window; do
		if [[ -n "$window" ]]; then
			local display_title address
			display_title=$(echo "$window" | jq -r '.display_title // empty' 2>/dev/null)
			address=$(echo "$window" | jq -r '.address // empty' 2>/dev/null)

			if [[ -n "$display_title" && -n "$address" ]]; then
				menu_options+="$display_title\n"
				window_addresses+=("$address")
			fi
		fi
	done < <(jq -c '.[]' "$CACHE_FILE" 2>/dev/null)

	# Build rofi command
	local rofi_cmd=(rofi -dmenu -i -p "Restore Window"
		-theme-str "entry { placeholder: \"⏰ Select window to restore\";}"
		-theme "${ROFI_MINIMIZER_STYLE:-clipboard}"
		-format "i"
		-no-custom)

	[[ -n "${rofi_position:-}" ]] && rofi_cmd+=(-theme-str "${rofi_position}")
	[[ -n "${font_override:-}" ]] && rofi_cmd+=(-theme-str "${font_override}")
	[[ -n "${r_override:-}" ]] && rofi_cmd+=(-theme-str "${r_override}")

	# Show menu and get selection
	local selected_index
	selected_index=$(echo -e "$menu_options" | "${rofi_cmd[@]}" 2>/dev/null)

	if [[ -n "$selected_index" && "$selected_index" =~ ^[0-9]+$ ]]; then
		local selected_address="${window_addresses[$selected_index]}"

		if [[ "$selected_address" == "RESTORE_ALL" ]]; then
			restore_all_windows
		elif [[ -n "$selected_address" ]]; then
			restore_specific_window "$selected_address"
		fi
	fi
}

# Function to restore window (with optional specific ID)
restore_window() {
	local window_id="$1"

	if [[ -n "$window_id" ]]; then
		restore_specific_window "$window_id"
	else
		show_restore_menu
	fi
}

# Function to minimize current window
minimize_window() {
	# Get active window info
	local window_info
	window_info=$(hyprctl activewindow -j 2>/dev/null)
	if [[ $? -ne 0 ]]; then
		echo "Failed to get active window info" >&2
		return 1
	fi

	local window_class
	window_class=$(parse_window_info "$window_info" "class")

	# Skip if it's wofi or rofi
	if [[ "$window_class" == "wofi" || "$window_class" == "rofi" ]]; then
		return 0
	fi

	local window_addr class_name title at size pid
	window_addr=$(parse_window_info "$window_info" "address")
	class_name=$(parse_window_info "$window_info" "class")
	title=$(parse_window_info "$window_info" "title")
	at=$(parse_window_info "$window_info" "at")
	size=$(parse_window_info "$window_info" "size")
	pid=$(parse_window_info "$window_info" "pid")

	if [[ -z "$window_addr" ]]; then
		echo "No window address found" >&2
		return 1
	fi

	local short_addr="${window_addr: -4}"
	local icon
	icon=$(get_app_icon "$class_name")

	# Get geometry for preview
	local geometry preview_path=""
	if [[ -n "$at" && -n "$size" ]]; then
		# Convert from JSON array format to geometry string
		local x y w h
		x=$(echo "$at" | jq -r '.[0]' 2>/dev/null)
		y=$(echo "$at" | jq -r '.[1]' 2>/dev/null)
		w=$(echo "$size" | jq -r '.[0]' 2>/dev/null)
		h=$(echo "$size" | jq -r '.[1]' 2>/dev/null)

		if [[ -n "$x" && -n "$y" && -n "$w" && -n "$h" ]]; then
			geometry="${w}x${h}+${x}+${y}"
			preview_path=$(capture_window_preview "$window_addr" "$geometry")
		fi
	fi

	# Create window JSON object
	local display_title
	display_title="$icon $class_name - $title [$short_addr]"

	local window_json
	window_json=$(jq -n \
		--arg addr "$window_addr" \
		--arg disp_title "$display_title" \
		--arg class "$class_name" \
		--arg orig_title "$title" \
		--arg preview "$preview_path" \
		--arg icon "$icon" \
		'{
            address: $addr,
            display_title: $disp_title,
            class: $class,
            original_title: $orig_title,
            preview: $preview,
            icon: $icon
        }')

	# Move window to special workspace
	local move_result
	move_result=$(hyprctl dispatch movetoworkspacesilent "special:minimum,address:${window_addr}" 2>&1)

	# Send SIGSTOP to the process
	notify-send -i "$icon" "Window Minimized: $display_title :: PID: $pid"
	# One way to do it
	# local sigstop_result
	# sigstop_result=$(hyprctl dispatch signal 19 2>&1)
	if [[ -n "$pid" && "$pid" =~ ^[0-9]+$ ]]; then
		# kill -s STOP "$pid" 2>/dev/null
		signal_process_tree "$pid" "STOP"
		if [[ $? -ne 0 ]]; then
			echo "Failed to stop process with PID $pid" >&2
		fi
	else
		echo "No valid PID found for the window" >&2
	fi

	if [[ $? -eq 0 ]]; then
		# Create cache directory if it doesn't exist
		mkdir -p "$CACHE_DIR"

		# Update cache file
		local existing_windows=()
		if [[ -f "$CACHE_FILE" ]]; then
			while IFS= read -r line; do
				[[ -n "$line" ]] && existing_windows+=("$line")
			done < <(jq -c '.[]' "$CACHE_FILE" 2>/dev/null || echo "")
		fi

		existing_windows+=("$window_json")
		create_json_output "${existing_windows[@]}" >"$CACHE_FILE"

		signal_waybar
		echo "Window minimized successfully" >&2
	else
		echo "Failed to minimize window: $move_result" >&2
		return 1
	fi
}

signal_process_tree() {
	local pid=$1
	local signal="${2:-STOP}"
	kill -s "$signal" "$pid" 2>/dev/null || return 1
	for child in $(pgrep -P "$pid"); do
		signal_process_tree "$child" "$signal" # Recursively stop child processes
	done
}

# Function to show status for waybar
show_status() {
	local count=0

	if [[ -f "$CACHE_FILE" ]]; then
		count=$(jq '. | length' "$CACHE_FILE" 2>/dev/null || echo "0")
	fi

	if [[ "$count" -gt 0 ]]; then
		echo "{\"text\":\"󰘸 $count\",\"class\":\"has-windows\",\"tooltip\":\"$count minimized windows\"}"
	else
		echo "{\"text\":\"󰘸\",\"class\":\"empty\",\"tooltip\":\"No minimized windows\"}"
	fi
}

# Main function
main() {
	# Create directories
	mkdir -p "$CACHE_DIR" "$PREVIEW_DIR"

	# Initialize cache file if it doesn't exist
	[[ ! -f "$CACHE_FILE" ]] && echo "[]" >"$CACHE_FILE"

	local command="$1"
	local window_id="$2"

	case "$command" in
	"--help")
		echo "Usage: $0 <command> [window_id]"
		echo "Commands:"
		echo "  minimize       Minimize the current window"
		echo "  restore        Restore a specific window by ID or show menu"
		echo "  restore-all    Restore all minimized windows"
		echo "  restore-last   Restore the last minimized window"
		echo "  show           Show status of minimized windows"
		exit 0
		;;
	"minimize")
		minimize_window
		;;
	"restore")
		restore_window "$window_id"
		;;
	"restore-all")
		restore_all_windows
		;;
	"restore-last")
		if [[ -f "$CACHE_FILE" ]]; then
			local last_window
			last_window=$(jq -r '.[-1].address // empty' "$CACHE_FILE" 2>/dev/null)
			[[ -n "$last_window" && "$last_window" != "null" ]] && restore_window "$last_window"
		fi
		;;
	"show")
		show_status
		;;
	*)
		echo "Unknown command: $command" >&2
		echo "Usage: $0 <command> [window_id]" >&2
		echo "Commands: minimize, restore, restore-all, restore-last, show" >&2
		exit 1
		;;
	esac
}

# Run main function with all arguments
main "$@"
