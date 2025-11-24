#!/usr/bin/env bash
# HyDE Waybar Manager Shell Wrapper
#
# Provides an easy-to-use CLI interface for the Lua waybar manager
# This script handles environment setup and delegates to waybar_manager.lua
#
# Usage: waybar [command] [args...]

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set up environment
export LUA_PATH="${SCRIPT_DIR}/?.lua;${LUA_PATH}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

print_error() {
	echo -e "${RED}error:${NC} $*" >&2
}

print_success() {
	echo -e "${GREEN}✓${NC} $*"
}

print_info() {
	echo -e "${BLUE}ℹ${NC} $*"
}

print_warning() {
	echo -e "${YELLOW}⚠${NC} $*"
}

print_usage() {
	cat <<EOF
${BLUE}HyDE Waybar Manager${NC}

Manage waybar configuration, layouts, and appearance settings.

${BLUE}Usage:${NC}
  waybar [COMMAND] [OPTIONS]

${BLUE}Commands:${NC}
  layout SUBCOMMAND [OPTIONS]
    Manage waybar layouts
    
    Subcommands:
      list                    List all available layouts
      current                 Show current layout
      set <name>              Set layout to <name>
      next                    Switch to next layout
      prev                    Switch to previous layout
      backup <name>           Create backup of layout <name>
      
  appearance [OPTIONS]
    Configure waybar appearance settings
    
    Options:
      --icon-size <size>      Set icon size (default: 16)
      --border-radius <px>    Set border radius (default: 8)
      --font-family <name>    Set font family (default: JetBrains Mono)
      --font-size <px>        Set font size (default: 10)
      
  config [OPTIONS]
    Manage waybar configuration
    
    Options:
      --generate              Generate configuration files
      --reload                Reload waybar configuration
      --validate              Validate current configuration
      --reset                 Reset to default configuration
      
  process [SUBCOMMAND]
    Control waybar process
    
    Subcommands:
      status                  Check if waybar is running
      start                   Start waybar
      stop                    Stop waybar
      restart                 Restart waybar
      watch                   Start waybar in watch mode (auto-restart on changes)
      
  state [OPTIONS]
    Manage application state
    
    Options:
      --get <key>             Get state value
      --set <key> <value>     Set state value
      --reset                 Reset state to defaults
      --show                  Show all state values
      
  theme [SUBCOMMAND]
    Manage theme and style
    
    Subcommands:
      list                    List available themes
      current                 Show current theme
      set <name>              Set theme to <name>
      apply                   Apply current theme
      
  --help, -h                  Show this help message
  --version, -v               Show version information
  --debug                     Enable debug output
  --json                      Output in JSON format

${BLUE}Examples:${NC}
  # List available layouts
  waybar layout list
  
  # Switch to next layout
  waybar layout next
  
  # Set custom icon size
  waybar appearance --icon-size 18
  
  # Check if waybar is running
  waybar process status
  
  # Start waybar in watch mode
  waybar process watch
  
  # Get current theme
  waybar theme current
  
  # Reset state to defaults
  waybar state --reset

${BLUE}Configuration Directories:${NC}
  Config: $XDG_CONFIG_HOME/waybar
  State:  $XDG_STATE_HOME/hyde
  Cache:  $XDG_CACHE_HOME/hyde
  Runtime: $XDG_RUNTIME_DIR

${BLUE}For more information, visit:${NC}
  https://github.com/sst/hyde

EOF
}

print_version() {
	echo "HyDE Waybar Manager v1.0.0"
	echo "Lua port with libuv"
}

# ============================================================================
# COMMAND HANDLERS
# ============================================================================

# Handle layout commands
handle_layout_cmd() {
	local subcmd="$1"
	shift || true
	
	case "$subcmd" in
		list)
			lua "$SCRIPT_DIR/waybar_manager.lua" --list-layouts "$@"
			;;
		current)
			lua "$SCRIPT_DIR/waybar_manager.lua" --current-layout "$@"
			;;
		set)
			local layout_name="$1"
			if [ -z "$layout_name" ]; then
				print_error "layout name required"
				echo "Usage: waybar layout set <name>"
				return 1
			fi
			lua "$SCRIPT_DIR/waybar_manager.lua" --set-layout "$layout_name" "$@"
			;;
		next)
			lua "$SCRIPT_DIR/waybar_manager.lua" --next-layout "$@"
			;;
		prev)
			lua "$SCRIPT_DIR/waybar_manager.lua" --prev-layout "$@"
			;;
		backup)
			local layout_name="$1"
			if [ -z "$layout_name" ]; then
				print_error "layout name required"
				echo "Usage: waybar layout backup <name>"
				return 1
			fi
			lua "$SCRIPT_DIR/waybar_manager.lua" --backup-layout "$layout_name" "$@"
			;;
		*)
			print_error "unknown layout subcommand: $subcmd"
			echo "Available subcommands: list, current, set, next, prev, backup"
			return 1
			;;
	esac
}

# Handle appearance commands
handle_appearance_cmd() {
	local icon_size=""
	local border_radius=""
	local font_family=""
	local font_size=""
	
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--icon-size)
				icon_size="$2"
				shift 2
				;;
			--border-radius)
				border_radius="$2"
				shift 2
				;;
			--font-family)
				font_family="$2"
				shift 2
				;;
			--font-size)
				font_size="$2"
				shift 2
				;;
			*)
				print_warning "unknown appearance option: $1"
				shift
				;;
		esac
	done
	
	# Call lua manager with appearance settings
	if [ -n "$icon_size" ]; then
		lua "$SCRIPT_DIR/waybar_manager.lua" --update-icon-size "$icon_size"
	fi
	if [ -n "$border_radius" ]; then
		lua "$SCRIPT_DIR/waybar_manager.lua" --update-border-radius "$border_radius"
	fi
	if [ -n "$font_family" ]; then
		lua "$SCRIPT_DIR/waybar_manager.lua" --update-font-family "$font_family"
	fi
	if [ -n "$font_size" ]; then
		lua "$SCRIPT_DIR/waybar_manager.lua" --update-font-size "$font_size"
	fi
	
	if [ -z "$icon_size$border_radius$font_family$font_size" ]; then
		print_info "no appearance options specified"
		echo "Usage: waybar appearance [--icon-size SIZE] [--border-radius PX] [--font-family NAME] [--font-size PX]"
	fi
}

# Handle config commands
handle_config_cmd() {
	local subcmd="$1"
	shift || true
	
	case "$subcmd" in
		generate)
			lua "$SCRIPT_DIR/waybar_manager.lua" --generate-config "$@"
			;;
		reload)
			lua "$SCRIPT_DIR/waybar_manager.lua" --reload-config "$@"
			;;
		validate)
			lua "$SCRIPT_DIR/waybar_manager.lua" --validate-config "$@"
			;;
		reset)
			lua "$SCRIPT_DIR/waybar_manager.lua" --reset-config "$@"
			;;
		*)
			print_error "unknown config subcommand: $subcmd"
			echo "Available subcommands: generate, reload, validate, reset"
			return 1
			;;
	esac
}

# Handle process commands
handle_process_cmd() {
	local subcmd="$1"
	shift || true
	
	case "$subcmd" in
		status)
			if lua "$SCRIPT_DIR/waybar_manager.lua" --is-waybar-running; then
				print_success "waybar is running"
			else
				print_warning "waybar is not running"
			fi
			;;
		start)
			print_info "starting waybar..."
			lua "$SCRIPT_DIR/waybar_manager.lua" --start-waybar "$@"
			print_success "waybar started"
			;;
		stop)
			print_info "stopping waybar..."
			lua "$SCRIPT_DIR/waybar_manager.lua" --stop-waybar "$@"
			print_success "waybar stopped"
			;;
		restart)
			print_info "restarting waybar..."
			lua "$SCRIPT_DIR/waybar_manager.lua" --restart-waybar "$@"
			print_success "waybar restarted"
			;;
		watch)
			print_info "starting waybar in watch mode..."
			lua "$SCRIPT_DIR/waybar_manager.lua" --watch-waybar "$@"
			;;
		*)
			print_error "unknown process subcommand: $subcmd"
			echo "Available subcommands: status, start, stop, restart, watch"
			return 1
			;;
	esac
}

# Handle state commands
handle_state_cmd() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--get)
				local key="$2"
				lua "$SCRIPT_DIR/waybar_manager.lua" --get-state "$key"
				shift 2
				;;
			--set)
				local key="$2"
				local value="$3"
				lua "$SCRIPT_DIR/waybar_manager.lua" --set-state "$key" "$value"
				shift 3
				;;
			--reset)
				lua "$SCRIPT_DIR/waybar_manager.lua" --reset-state
				shift
				;;
			--show)
				lua "$SCRIPT_DIR/waybar_manager.lua" --show-state
				shift
				;;
			*)
				print_warning "unknown state option: $1"
				shift
				;;
		esac
	done
}

# Handle theme commands
handle_theme_cmd() {
	local subcmd="$1"
	shift || true
	
	case "$subcmd" in
		list)
			lua "$SCRIPT_DIR/waybar_manager.lua" --list-themes "$@"
			;;
		current)
			lua "$SCRIPT_DIR/waybar_manager.lua" --current-theme "$@"
			;;
		set)
			local theme_name="$1"
			if [ -z "$theme_name" ]; then
				print_error "theme name required"
				echo "Usage: waybar theme set <name>"
				return 1
			fi
			lua "$SCRIPT_DIR/waybar_manager.lua" --set-theme "$theme_name" "$@"
			;;
		apply)
			lua "$SCRIPT_DIR/waybar_manager.lua" --apply-theme "$@"
			;;
		*)
			print_error "unknown theme subcommand: $subcmd"
			echo "Available subcommands: list, current, set, apply"
			return 1
			;;
	esac
}

# ============================================================================
# MAIN
# ============================================================================

# Check if Lua is available
if ! command -v lua &> /dev/null && ! command -v lua5.1 &> /dev/null; then
	print_error "lua is not installed or not in PATH"
	exit 1
fi

# Handle no arguments
if [ $# -eq 0 ]; then
	print_usage
	exit 0
fi

# Parse main command
case "$1" in
	layout)
		shift
		handle_layout_cmd "$@"
		;;
	appearance)
		shift
		handle_appearance_cmd "$@"
		;;
	config)
		shift
		handle_config_cmd "$@"
		;;
	process)
		shift
		handle_process_cmd "$@"
		;;
	state)
		shift
		handle_state_cmd "$@"
		;;
	theme)
		shift
		handle_theme_cmd "$@"
		;;
	--help|-h)
		print_usage
		exit 0
		;;
	--version|-v)
		print_version
		exit 0
		;;
	--debug)
		export DEBUG=1
		shift
		if [ $# -eq 0 ]; then
			print_info "debug mode enabled"
			exit 0
		fi
		# Continue with next command
		"$0" "$@"
		;;
	--json)
		export JSON_OUTPUT=1
		shift
		if [ $# -eq 0 ]; then
			print_error "command required"
			exit 1
		fi
		# Continue with next command
		"$0" "$@"
		;;
	*)
		print_error "unknown command: $1"
		echo "Use 'waybar --help' to see available commands"
		exit 1
		;;
esac
