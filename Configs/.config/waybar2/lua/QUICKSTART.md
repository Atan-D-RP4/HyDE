# Quick Start Guide - HyDE Waybar Lua Manager

## Installation

### 1. Prerequisites
```bash
# Install Lua 5.1 and dependencies
sudo pacman -S lua51 luv dkjson  # Arch
sudo apt install lua5.1 lua-luvit liblua5.1-dev  # Ubuntu/Debian
```

### 2. Copy Lua modules
```bash
# Modules are already in ~/.config/waybar2/lua/
ls -la ~/.config/waybar2/lua/
```

### 3. Make wrapper executable
```bash
chmod +x ~/.config/waybar2/lua/waybar
```

### 4. Optional: Add to PATH
```bash
ln -s ~/.config/waybar2/lua/waybar ~/.local/bin/waybar.lua
# Or update PATH in shell config
export PATH="$PATH:$HOME/.config/waybar2/lua"
```

## Basic Usage

### Initialize waybar
```bash
~/.config/waybar2/lua/waybar
```

### Switch layouts
```bash
# Next layout
~/.config/waybar2/lua/waybar --next

# Previous layout  
~/.config/waybar2/lua/waybar --prev

# Set specific layout
~/.config/waybar2/lua/waybar --set mydots
```

### View available layouts
```bash
~/.config/waybar2/lua/waybar --json | jq '.layouts[].name'
```

### Update configuration
```bash
# Update everything
~/.config/waybar2/lua/waybar --update

# Update just icon sizes
~/.config/waybar2/lua/waybar --update-icon-size
```

### Process management
```bash
# Start watching (auto-restart if crashed)
~/.config/waybar2/lua/waybar --watch &

# Stop waybar
~/.config/waybar2/lua/waybar --kill

# Toggle waybar visibility
~/.config/waybar2/lua/waybar --hide
```

## Troubleshooting

### Module not found errors
```bash
# Check LUA_PATH
export LUA_PATH="$HOME/.config/waybar2/lua/?.lua;$LUA_PATH"

# Or use the wrapper script which sets it automatically
```

### Waybar not starting
```bash
# Check if waybar is installed
which waybar

# Check if hyde-shell is available (optional)
which hyde-shell

# Run waybar manually to see errors
waybar
```

### Layout not applying
```bash
# Verify state file exists
cat ~/.local/state/hyde/staterc

# Check layout files
ls ~/.config/waybar/layouts/

# Force re-initialization
rm ~/.local/state/hyde/staterc
~/.config/waybar2/lua/waybar
```

### Debug output
```bash
# Enable debug logging (if implemented)
export WAYBAR_DEBUG=1
~/.config/waybar2/lua/waybar --update
```

## Module Files

The implementation consists of:

| File | Purpose |
|------|---------|
| `utils.lua` | Core utilities (file I/O, process mgmt, JSON) |
| `state_manager.lua` | State file and config management |
| `layout_manager.lua` | Layout discovery and management |
| `waybar_manager.lua` | Main waybar config manager |
| `waybar` | Bash wrapper script |
| `wb_modules.lua` | Waybar module definitions (existing) |
| `wb_presets.lua` | Waybar presets (existing) |

## Integration with HyDE

The manager works seamlessly with HyDE:

```bash
# Source environment from HyDE
source ~/.local/state/hyde/environment
source ~/.local/state/hyde/config

# Use with HyDE's shell launcher
hyde-shell app -- waybar

# Or direct execution
waybar
```

## Configuration Files

### State file
```bash
~/.local/state/hyde/staterc
# Contains:
# WAYBAR_LAYOUT_PATH=/path/to/layout.jsonc
# WAYBAR_LAYOUT_NAME=layoutname
# WAYBAR_STYLE_PATH=/path/to/style.css
```

### Main config
```bash
~/.config/waybar/config.jsonc
# Generated from current layout
```

### Styles
```bash
~/.config/waybar/style.css           # Main style file
~/.config/waybar/theme.css           # Theme colors
~/.config/waybar/user-style.css      # User overrides
~/.config/waybar/includes/global.css # Generated globals
~/.config/waybar/includes/border-radius.css # Generated borders
```

## Performance Tips

1. **First run** - Initialization may take 1-2 seconds
2. **Layout switching** - Usually 50-100ms
3. **Icon updates** - Usually 20-50ms
4. **Restart cycle** - Usually 1-2 seconds

## Advanced Usage

### Watch mode with logging
```bash
# Terminal 1: Watch for crashes
~/.config/waybar2/lua/waybar --watch

# Terminal 2: Check logs
journalctl --user -u waybar -f  # if using systemd
```

### List layouts programmatically
```bash
# Get JSON output for scripting
~/.config/waybar2/lua/waybar --json | jq '.layouts'

# Filter by name
~/.config/waybar2/lua/waybar --json | jq '.layouts[] | select(.name | contains("minimal"))'
```

### Create layout switcher script
```bash
#!/bin/bash
layouts=$($HOME/.config/waybar2/lua/waybar --json | jq -r '.layouts[].name')
selected=$(echo "$layouts" | rofi -dmenu -p "Layout")
[ -n "$selected" ] && $HOME/.config/waybar2/lua/waybar --set "$selected"
```

### Monitor configuration changes
```bash
# Watch config file for changes
watch -n 1 'stat ~/.config/waybar/config.jsonc'

# Check state updates
watch -n 0.5 'cat ~/.local/state/hyde/staterc'
```

## Helpful Aliases

Add to your shell config (~/.bashrc, ~/.zshrc, etc.):

```bash
# Waybar management
alias wbar="$HOME/.config/waybar2/lua/waybar"
alias wbar-next="wbar --next"
alias wbar-prev="wbar --prev"
alias wbar-kill="wbar --kill"
alias wbar-watch="wbar --watch &"
alias wbar-layouts="wbar --json | jq '.layouts[].name'"
alias wbar-set="wbar --set"
```

Then use:
```bash
wbar-next              # Switch to next layout
wbar-layouts           # List all layouts
wbar-set minimalist    # Set specific layout
```

## Migrating from Python

If you were using waybar.py before:

1. **Same interface** - All commands work the same way
2. **Same state** - Existing state files are compatible
3. **Same layouts** - All existing layouts work
4. **Same styles** - CSS files unchanged

Just replace `python ~/path/waybar.py` with `~/.config/waybar2/lua/waybar`

## Getting Help

```bash
# Show all available commands
~/.config/waybar2/lua/waybar --help

# Check module documentation
cat ~/.config/waybar2/lua/README.md

# View implementation details
cat ~/.config/waybar2/lua/IMPLEMENTATION.md
```

## Next Steps

1. **Customize layouts** - Edit ~/.config/waybar/layouts/
2. **Create styles** - Add CSS to ~/.config/waybar/styles/
3. **Configure modules** - Edit ~/.config/waybar2/modules/
4. **Automate** - Create shell scripts for common tasks
5. **Integrate** - Use with HyDE's configuration system

## See Also

- Original README: `README.md`
- Implementation guide: `IMPLEMENTATION.md`
- Module definitions: `wb_modules.lua`
- Configuration presets: `wb_presets.lua`
