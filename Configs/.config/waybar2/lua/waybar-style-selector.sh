#!/usr/bin/env bash
# Rofi-based Style Selector for HyDE Waybar
#
# Provides an interactive menu to browse and select waybar styles
# Can be bound to a keybinding for quick style switching
#
# Usage: waybar-style-selector [options]

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

WAYBAR_CONFIG="${XDG_CONFIG_HOME}/waybar"
WAYBAR_DATA="${XDG_DATA_HOME}/waybar"
WAYBAR_MANAGER="$SCRIPT_DIR/waybar_manager.lua"
STATE_FILE="${XDG_STATE_HOME}/hyde/staterc"

# Rofi configuration
ROFI_THEME="${ROFI_THEME:--}"
ROFI_LOCATION="${ROFI_LOCATION:-0}"
ROFI_LINES="${ROFI_LINES:-10}"
ROFI_COLUMNS="${ROFI_COLUMNS:-1}"
ROFI_WIDTH="${ROFI_WIDTH:-40}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

print_error() {
	echo -e "${RED}error:${NC} $*" >&2
}

print_success() {
	echo -e "${GREEN}✓${NC} $*"
}

# Check if command exists
check_command() {
	if ! command -v "$1" &> /dev/null; then
		print_error "$1 is not installed or not in PATH"
		return 1
	fi
	return 0
}

# Get list of available styles
get_styles() {
	local styles=()
	
	# Search in config/waybar/styles
	if [ -d "$WAYBAR_CONFIG/styles" ]; then
		while IFS= read -r file; do
			styles+=("$(basename "$file")")
		done < <(find "$WAYBAR_CONFIG/styles" -maxdepth 1 -name "*.css" -type f | grep -v "backup" | sort)
	fi
	
	# Search in share/waybar/styles
	if [ -d "$WAYBAR_DATA/styles" ]; then
		while IFS= read -r file; do
			local basename="$(basename "$file")"
			# Only add if not already in array
			if [[ ! " ${styles[@]} " =~ " ${basename} " ]]; then
				styles+=("$basename")
			fi
		done < <(find "$WAYBAR_DATA/styles" -maxdepth 1 -name "*.css" -type f | grep -v "backup" | sort)
	fi
	
	# Remove .css extension and print
	for style in "${styles[@]}"; do
		echo "${style%.css}"
	done
}

# Get current style from state file
get_current_style() {
	if [ -f "$STATE_FILE" ]; then
		# Read WAYBAR_STYLE_PATH from state file
		local style_path=$(grep "^WAYBAR_STYLE_PATH=" "$STATE_FILE" | cut -d= -f2-)
		
		if [ -n "$style_path" ]; then
			# Extract basename without extension
			basename "${style_path%.css}" | sed 's/\.css$//'
			return 0
		fi
	fi
	
	# Fallback: return defaults
	echo "defaults"
	return 0
}

# Resolve style path
resolve_style_path() {
	local style_name="$1"
	
	# Try in config/waybar/styles first
	if [ -f "$WAYBAR_CONFIG/styles/$style_name.css" ]; then
		echo "$WAYBAR_CONFIG/styles/$style_name.css"
		return 0
	fi
	
	# Try in share/waybar/styles
	if [ -f "$WAYBAR_DATA/styles/$style_name.css" ]; then
		echo "$WAYBAR_DATA/styles/$style_name.css"
		return 0
	fi
	
	# Pattern matching in config dir
	local match=$(find "$WAYBAR_CONFIG/styles" -maxdepth 1 -name "${style_name}*.css" -type f 2>/dev/null | head -1)
	if [ -n "$match" ]; then
		echo "$match"
		return 0
	fi
	
	# Pattern matching in data dir
	match=$(find "$WAYBAR_DATA/styles" -maxdepth 1 -name "${style_name}*.css" -type f 2>/dev/null | head -1)
	if [ -n "$match" ]; then
		echo "$match"
		return 0
	fi
	
	return 1
}

# Format style list for rofi
format_style_list() {
	local current="$1"
	shift
	local styles=("$@")
	
	for style in "${styles[@]}"; do
		if [ "$style" = "$current" ]; then
			echo "✓ $style"
		else
			echo "  $style"
		fi
	done
}

# Launch rofi selector
launch_rofi() {
	local current="$1"
	shift
	local styles=("$@")
	
	# Create temporary file for rofi input
	local tmpfile=$(mktemp)
	trap "rm -f $tmpfile" EXIT
	
	# Write styles to temp file
	format_style_list "$current" "${styles[@]}" > "$tmpfile"
	
	# Launch rofi with file input
	rofi -dmenu \
		-theme "$ROFI_THEME" \
		-location "$ROFI_LOCATION" \
		-lines "$ROFI_LINES" \
		-columns "$ROFI_COLUMNS" \
		-width "$ROFI_WIDTH" \
		-p "Select Style:" \
		< "$tmpfile"
}

# Parse rofi selection
parse_selection() {
	local selection="$1"
	
	# Remove the checkmark and leading spaces
	echo "$selection" | sed 's/^[✓ ]*//'
}

# Apply selected style
apply_style() {
	local style_name="$1"
	
	if [ -z "$style_name" ]; then
		print_error "style name is empty"
		return 1
	fi
	
	# Resolve full path
	local style_path=$(resolve_style_path "$style_name")
	if [ -z "$style_path" ]; then
		print_error "style not found: $style_name"
		return 1
	fi
	
	# Call the manager to apply the style
	if lua "$WAYBAR_MANAGER" --style "$style_path"; then
		print_success "Applied style: $style_name"
		
		# Send notification if notify-send is available
		if command -v notify-send &> /dev/null; then
			notify-send -t 2000 -r 9 "Waybar" "Style changed to $style_name"
		fi
		
		return 0
	else
		print_error "failed to apply style: $style_name"
		return 1
	fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
	# Check dependencies
	check_command "rofi" || exit 1
	check_command "lua" || exit 1
	
	# Get current style
	current_style=$(get_current_style)
	
	# Get available styles
	styles_array=()
	while IFS= read -r line; do
		[ -n "$line" ] && styles_array+=("$line")
	done < <(get_styles)
	
	if [ ${#styles_array[@]} -eq 0 ]; then
		print_error "no styles found"
		exit 1
	fi
	
	# Launch rofi selector
	selection=$(launch_rofi "$current_style" "${styles_array[@]}")
	
	# If user cancelled (selection is empty), exit
	if [ -z "$selection" ]; then
		exit 0
	fi
	
	# Parse selection and remove decorations
	selected_style=$(parse_selection "$selection")
	
	# Apply the selected style
	apply_style "$selected_style"
}

# ============================================================================
# ALTERNATIVE MODES
# ============================================================================

case "${1:-}" in
	--list)
		# List styles (useful for scripting)
		get_styles
		;;
	--current)
		# Show current style
		get_current_style
		;;
	--set)
		# Set style directly (useful for keybindings)
		if [ -z "$2" ]; then
			print_error "style name required"
			exit 1
		fi
		apply_style "$2"
		;;
	--help|-h)
		cat <<EOF
HyDE Waybar Rofi Style Selector

Interactive menu to browse and select waybar styles.

Usage:
  waybar-style-selector [OPTIONS]

Options:
  --list              List all available styles
  --current           Show current style
  --set <name>        Apply style <name> directly
  --help, -h          Show this help message

Environment Variables:
  ROFI_THEME          Rofi theme to use (default: -)
  ROFI_LOCATION       Window location (default: 0 = center)
  ROFI_LINES          Number of visible lines (default: 10)
  ROFI_COLUMNS        Number of columns (default: 1)
  ROFI_WIDTH          Window width as percentage (default: 40)

Examples:
  # Interactive selector
  waybar-style-selector

  # List styles
  waybar-style-selector --list

  # Direct selection
  waybar-style-selector --set "hyprdots"

  # Set theme and dimensions
  ROFI_THEME="nord" ROFI_LINES=15 waybar-style-selector

Keybinding Example (Hyprland):
  bind = $mainMod SHIFT, S, exec, waybar-style-selector

EOF
		;;
	*)
		# Launch interactive selector
		main
		;;
esac
