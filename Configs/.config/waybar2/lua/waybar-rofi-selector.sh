#!/usr/bin/env bash
# Rofi-based Layout Selector for HyDE Waybar
#
# Provides an interactive menu to browse and select waybar layouts
# Can be bound to a keybinding for quick layout switching
#
# Usage: waybar-rofi-selector [options]

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

WAYBAR_CONFIG="${XDG_CONFIG_HOME}/waybar"
WAYBAR_MANAGER="$SCRIPT_DIR/waybar_manager.lua"

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

# Get list of available layouts
get_layouts() {
	local layouts_dir="$WAYBAR_CONFIG/layouts"
	
	if [ ! -d "$layouts_dir" ]; then
		print_error "layouts directory not found: $layouts_dir"
		return 1
	fi
	
	# Find all .jsonc layout files and extract just the basename
	find "$layouts_dir" -maxdepth 1 -name "*.jsonc" -type f -printf '%f\n' | \
		sed 's/\.jsonc$//' | \
		sort
}

# Get current layout
get_current_layout() {
	if [ -f "$XDG_STATE_HOME/hyde/hyde.state.json" ]; then
		# Try to extract current_layout from JSON
		local layout=$(grep -o '"current_layout"\s*:\s*"[^"]*"' "$XDG_STATE_HOME/hyde/hyde.state.json" | \
			sed 's/"current_layout"\s*:\s*"//' | \
			sed 's/".*//')
		
		if [ -n "$layout" ]; then
			echo "$layout"
			return 0
		fi
	fi
	
	# Fallback: return default
	echo "default"
	return 0
}

# Format layout list for rofi
format_layout_list() {
	local current="$1"
	local layouts=("${@:2}")
	
	for layout in "${layouts[@]}"; do
		if [ "$layout" = "$current" ]; then
			echo "✓ $layout"
		else
			echo "  $layout"
		fi
	done
}

# Launch rofi selector
launch_rofi() {
	local current="$1"
	shift
	local layouts=("$@")
	
	# Create temporary file for rofi input
	local tmpfile=$(mktemp)
	trap "rm -f $tmpfile" EXIT
	
	# Write layouts to temp file
	format_layout_list "$current" "${layouts[@]}" > "$tmpfile"
	
	# Launch rofi with file input
	rofi -dmenu \
		-theme "$ROFI_THEME" \
		-location "$ROFI_LOCATION" \
		-lines "$ROFI_LINES" \
		-columns "$ROFI_COLUMNS" \
		-width "$ROFI_WIDTH" \
		-p "Select Layout:" \
		< "$tmpfile"
}

# Parse rofi selection
parse_selection() {
	local selection="$1"
	
	# Remove the checkmark and leading spaces
	echo "$selection" | sed 's/^[✓ ]*//'
}

# Apply selected layout
apply_layout() {
	local layout_name="$1"
	
	if [ -z "$layout_name" ]; then
		print_error "layout name is empty"
		return 1
	fi
	
	# Verify layout exists
	if [ ! -f "$WAYBAR_CONFIG/layouts/$layout_name.jsonc" ]; then
		print_error "layout not found: $layout_name"
		return 1
	fi
	
	# Call the manager to apply the layout
	if lua "$WAYBAR_MANAGER" --set-layout "$layout_name"; then
		print_success "Applied layout: $layout_name"
		return 0
	else
		print_error "failed to apply layout: $layout_name"
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
	
	# Get current layout
	current_layout=$(get_current_layout)
	
	# Get available layouts
	layouts_array=()
	while IFS= read -r line; do
		[ -n "$line" ] && layouts_array+=("$line")
	done < <(get_layouts)
	
	if [ ${#layouts_array[@]} -eq 0 ]; then
		print_error "no layouts found"
		exit 1
	fi
	
	# Launch rofi selector
	selection=$(launch_rofi "$current_layout" "${layouts_array[@]}")
	
	# If user cancelled (selection is empty), exit
	if [ -z "$selection" ]; then
		exit 0
	fi
	
	# Parse selection and remove decorations
	selected_layout=$(parse_selection "$selection")
	
	# Apply the selected layout
	apply_layout "$selected_layout"
}

# ============================================================================
# ALTERNATIVE MODES
# ============================================================================

case "${1:-}" in
	--list)
		# List layouts (useful for scripting)
		get_layouts
		;;
	--current)
		# Show current layout
		get_current_layout
		;;
	--set)
		# Set layout directly (useful for keybindings)
		if [ -z "$2" ]; then
			print_error "layout name required"
			exit 1
		fi
		apply_layout "$2"
		;;
	--help|-h)
		cat <<EOF
HyDE Waybar Rofi Layout Selector

Interactive menu to browse and select waybar layouts.

Usage:
  waybar-rofi-selector [OPTIONS]

Options:
  --list              List all available layouts
  --current           Show current layout
  --set <name>        Apply layout <name> directly
  --help, -h          Show this help message

Environment Variables:
  ROFI_THEME          Rofi theme to use (default: -)
  ROFI_LOCATION       Window location (default: 0 = center)
  ROFI_LINES          Number of visible lines (default: 10)
  ROFI_COLUMNS        Number of columns (default: 1)
  ROFI_WIDTH          Window width as percentage (default: 40)

Examples:
  # Interactive selector
  waybar-rofi-selector

  # List layouts
  waybar-rofi-selector --list

  # Direct selection
  waybar-rofi-selector --set "my-layout"

  # Set theme and dimensions
  ROFI_THEME="nord" ROFI_LINES=15 waybar-rofi-selector

Keybinding Example (Hyprland):
  bind = $mainMod, L, exec, waybar-rofi-selector

EOF
		;;
	*)
		# Launch interactive selector
		main
		;;
esac
