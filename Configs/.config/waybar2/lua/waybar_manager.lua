#!/usr/bin/env lua5.1
--[[
  HyDE Waybar Configuration Manager in Lua with libuv
  
  Main module that replaces waybar.py - manages waybar configuration,
  layouts, styles, and process lifecycle using libuv for async I/O
  and process management.
]]

local json = require("dkjson")
local uv = require("luv") or require("luvit.uv")

-- Import local modules
local Utils = require("utils")
local StateManager = require("state_manager")
local LayoutManager = require("layout_manager")

-- Session information
local XDG_SESSION_DESKTOP = os.getenv("XDG_SESSION_DESKTOP") or "unknown"

local WaybarManager = {}
WaybarManager.__index = WaybarManager

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function WaybarManager.new()
	local obj = {
		config_dir = Utils.get_xdg_dir("config") .. "/waybar",
		state_dir = Utils.get_xdg_dir("state") .. "/hyde",
		cache_dir = Utils.get_xdg_dir("cache") .. "/hyde",
		runtime_dir = Utils.get_xdg_dir("runtime"),
	}
	setmetatable(obj, self)
	return obj
end

-- ============================================================================
-- PROCESS MANAGEMENT
-- ============================================================================

--- Check if waybar is running
---@return boolean
function WaybarManager:is_waybar_running()
	local output, _, code = Utils.run_command("pgrep", { "-x", "waybar" })
	return code == 0 and output:match("%d+") ~= nil
end

--- Run waybar via custom script or direct execution
---@return boolean success
function WaybarManager:run_waybar()
	if self:is_waybar_running() then
		Utils.debug("Waybar already running")
		return true
	end

	Utils.debug("Starting waybar")
	
	-- Try using hyde-shell if available
	local _, _, code = Utils.run_command("which", { "hyde-shell" })
	if code == 0 then
		Utils.spawn_async("hyde-shell", { "app", "--", "waybar" })
	else
		-- Fallback to direct execution
		Utils.spawn_async("waybar", {})
	end
	
	return true
end

--- Kill waybar process
---@return boolean success
function WaybarManager:kill_waybar()
	Utils.debug("Stopping waybar")
	return Utils.kill_process("waybar", 15)  -- SIGTERM
end

--- Restart waybar
---@return boolean success
function WaybarManager:restart_waybar()
	Utils.debug("Restarting waybar")
	self:kill_waybar()
	-- Wait a bit for process to die
	uv.sleep(500)
	return self:run_waybar()
end

--- Send signal to waybar process
---@param signal string
---@return boolean success
function WaybarManager:send_signal_to_waybar(signal)
	local sig_num = signal == "SIGUSR1" and 10 or 15
	return Utils.kill_process("waybar", sig_num)
end

--- Watch and auto-restart waybar if it dies
function WaybarManager:watch()
	Utils.info("Watching waybar process")
	local check_interval = 2000  -- 2 seconds

	local function check_and_restart()
		if not self:is_waybar_running() then
			Utils.info("Waybar process died, restarting...")
			self:run_waybar()
		end
	end

	-- Register signal handlers
	uv.new_signal():start("sigint", function()
		Utils.info("Received SIGINT, shutting down watcher")
		self:kill_waybar()
		os.exit(0)
	end)

	uv.new_signal():start("sigterm", function()
		Utils.info("Received SIGTERM, shutting down watcher")
		self:kill_waybar()
		os.exit(0)
	end)

	-- Check periodically
	local timer = uv.new_timer()
	timer:start(check_interval, check_interval, check_and_restart)
	uv.run()
end

-- ============================================================================
-- CONFIGURATION UPDATES
-- ============================================================================

--- Update icon sizes in JSON includes
function WaybarManager:update_icon_size()
	Utils.info("Updating icon sizes")

	local includes_file = self.config_dir .. "/includes/includes.json"
	Utils.mkdir_p(self.config_dir .. "/includes")

	local includes_data = { include = {} }
	if Utils.file_exists(includes_file) then
		local data, err = Utils.json_load(includes_file)
		if not err then
			includes_data = data
		end
	end

	local icon_size = self:get_waybar_icon_size()
	local updated_entries = {}

	for _, module_dir in ipairs(LayoutManager.MODULE_DIRS) do
		if Utils.file_exists(module_dir) then
			local files = Utils.list_files(module_dir, "%.json$", false)
			for _, json_file in ipairs(files) do
				local data, err = Utils.json_load(json_file)
				if not err and type(data) == "table" then
					for key, value in pairs(data) do
						if type(value) == "table" then
							local multiplier = value["icon-size-multiplier"] or 1
							local final_size = math.floor(icon_size * multiplier)
							value["icon-size"] = final_size
							value["tooltip-icon-size"] = final_size
							value["size"] = final_size
							updated_entries[key] = value
						end
					end
				end
			end
		end
	end

	for key, value in pairs(updated_entries) do
		includes_data[key] = value
	end

	Utils.json_save(includes_file, includes_data)
	Utils.info("Updated icon sizes in " .. includes_file)
end

--- Generate global.css with font configuration
function WaybarManager:update_global_css()
	Utils.info("Updating global CSS")

	local global_css_path = self.config_dir .. "/includes/global.css"
	Utils.mkdir_p(self.config_dir .. "/includes")

	local font_family = self:get_waybar_font_family()
	local font_size = self:get_waybar_font_size()

	if font_family then
		font_family = font_family:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
	end

	local css_content = [[/*
 Dynamic Style Configuration
 This is handled by HyDE

 To generate a dynamic configuration
 based on theme and user settings
*/

* {
	border-radius: 0em;
	font-family: "]] .. font_family .. [[","JetBrainsMono Nerd Font";
	font-size: ]] .. font_size .. [[px;
}
]]

	Utils.write_file(global_css_path, css_content)
	Utils.debug("Generated global CSS at " .. global_css_path)
end

--- Update border radius in CSS
function WaybarManager:update_border_radius()
	Utils.info("Updating border radius")

	local css_filepath = self.config_dir .. "/includes/border-radius.css"
	Utils.mkdir_p(self.config_dir .. "/includes")

	-- Copy template if doesn't exist
	if not Utils.file_exists(css_filepath) then
		for _, includes_dir in ipairs(LayoutManager.STYLE_DIRS) do
			local template_path = includes_dir .. "/border-radius.css"
			if Utils.file_exists(template_path) then
				local content, err = Utils.read_file(template_path)
				if not err then
					Utils.write_file(css_filepath, content)
					break
				end
			end
		end
	end

	local border_radius = os.getenv("WAYBAR_BORDER_RADIUS")

	-- Try to get from theme
	if not border_radius then
		local theme_name = StateManager.get_state_value("HYDE_THEME")
		if theme_name then
			local hypr_theme = Utils.get_xdg_dir("config") .. "/hyde/themes/" .. theme_name .. "/hypr.theme"
			if Utils.file_exists(hypr_theme) then
				local output, _, code = Utils.run_command("hyq", {
					hypr_theme, "--query", "decoration:rounding"
				})
				if code == 0 then
					border_radius = output:match("%d+")
				end
			end
		end
	end

	-- Fallback to hyprctl
	if not border_radius then
		local output, _, code = Utils.run_command("hyprctl", {
			"getoption", "decoration:rounding", "-j"
		})
		if code == 0 then
			local data, err = Utils.json_decode(output)
			if not err and data.int then
				border_radius = tostring(data.int)
			end
		end
	end

	border_radius = border_radius or "2"
	if tonumber(border_radius) < 1 then
		border_radius = "2"
	end

	-- Apply to CSS file
	if Utils.file_exists(css_filepath) then
		local content, err = Utils.read_file(css_filepath)
		if not err then
			content = content:gsub("%d+pt", border_radius .. "pt")
			Utils.write_file(css_filepath, content)
		end
	end

	Utils.debug("Updated border radius to " .. border_radius)
end

--- Generate includes.json with module list
function WaybarManager:generate_includes()
	Utils.info("Generating includes")

	local includes_file = self.config_dir .. "/includes/includes.json"
	Utils.mkdir_p(self.config_dir .. "/includes")

	local includes_data = { include = {} }
	if Utils.file_exists(includes_file) then
		local data, err = Utils.json_load(includes_file)
		if not err then
			includes_data = data
		end
	end

	local includes = {}
	for _, module_dir in ipairs(LayoutManager.MODULE_DIRS) do
		if Utils.file_exists(module_dir) then
			local json_files = Utils.list_files(module_dir, "%.json$", false)
			for _, file in ipairs(json_files) do
				if not Utils.split(file, "\n")[1] or Utils.split(file, "\n")[1] ~= "" then
					table.insert(includes, file)
				end
			end
			local jsonc_files = Utils.list_files(module_dir, "%.jsonc$", false)
			for _, file in ipairs(jsonc_files) do
				table.insert(includes, file)
			end
		end
	end

	-- Deduplicate
	local seen = {}
	local unique = {}
	for _, file in ipairs(includes) do
		if not seen[file] then
			table.insert(unique, file)
			seen[file] = true
		end
	end

	includes_data.include = unique

	-- Get position from config
	local position = StateManager.get_config_value("WAYBAR_POSITION") or "top"
	position = position:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
	includes_data.position = position

	Utils.json_save(includes_file, includes_data)
	Utils.info("Generated includes with " .. tostring(#unique) .. " entries")
end

-- ============================================================================
-- CONFIGURATION GETTERS
-- ============================================================================

--- Get font family from config or theme
---@return string font_family
function WaybarManager:get_waybar_font_family()
	-- Priority: WAYBAR_FONT config > hypr.theme > state file
	local font = StateManager.get_config_value("WAYBAR_FONT")
	if font then
		return font:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
	end

	-- Try from hypr.theme
	local theme_name = StateManager.get_state_value("HYDE_THEME")
	if theme_name then
		local hypr_theme = Utils.get_xdg_dir("config") .. "/hyde/themes/" .. theme_name .. "/hypr.theme"
		if Utils.file_exists(hypr_theme) then
			local output, _, code = Utils.run_command("hyq", {
				hypr_theme, "--query", "$BAR_FONT"
			})
			if code == 0 then
				return output:match("^[^\n]+"):gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
			end
		end
	end

	-- Try from state file
	font = StateManager.get_state_value("BAR_FONT")
	if font then
		return font:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
	end

	return "JetBrainsMono Nerd Font"
end

--- Get font size
---@return number font_size
function WaybarManager:get_waybar_font_size()
	local size = StateManager.get_config_value("WAYBAR_SCALE")
	if size then
		return tonumber(size) or 10
	end

	size = StateManager.get_state_value("BAR_FONT_SIZE")
	if size then
		return tonumber(size) or 10
	end

	size = StateManager.get_state_value("BAR_FONT_SIZE")
	if size then
		return tonumber(size) or 10
	end

	return 10
end

--- Get icon size
---@return number icon_size
function WaybarManager:get_waybar_icon_size()
	local size = StateManager.get_config_value("WAYBAR_ICON_SIZE")
	if size then
		return tonumber(size) or 10
	end

	size = StateManager.get_config_value("WAYBAR_SCALE")
	if size then
		return tonumber(size) or 10
	end

	size = StateManager.get_state_value("BAR_ICON_SIZE")
	if size then
		return tonumber(size) or 10
	end

	return 10
end

-- ============================================================================
-- STYLE MANAGEMENT
-- ============================================================================

--- Write style.css file with imports
---@param style_path string
function WaybarManager:write_style_file(style_path)
	Utils.debug("Writing style file")

	local wallbash_gtk = self.cache_dir .. "/wallbash/gtk.css"
	local wallbash_import = ""
	if Utils.file_exists(wallbash_gtk) then
		wallbash_import = '@import "' .. wallbash_gtk .. '";'
	else
		wallbash_import = "/*  wallbash gtk.css not found   */"
	end

	local css_content = [[
/*!  DO NOT EDIT THIS FILE */
/*
*     ░▒▒▒░░░▓▓           ___________
*   ░░▒▒▒░░░░░▓▓        //___________/
*  ░░▒▒▒░░░░░▓▓     _   _ _    _ _____
*  ░░▒▒░░░░░▓▓▓▓▓ | | | | |  | |  __/
*   ░▒▒░░░░▓▓   ▓▓ | |_| | |_/ /| |___
*    ░▒▒░▓▓   ▓▓   |__  |____/ |____/
*      ░▒▓▓   ▓▓  //____/
*/

/* Modified by Hyde */

/* Modify/add style in ~/.config/waybar/styles/ */
@import "]] .. style_path .. [[";

/* Imports wallbash colors */
]] .. wallbash_import .. [[

/* Colors and theme configuration is generated through the `theme.css` file */
@import "theme.css";

/* Users who want to override the current style add/edit 'user-style.css' */
@import "user-style.css";
]]

	local style_filepath = self.config_dir .. "/style.css"
	Utils.write_file(style_filepath, css_content)
	Utils.debug("Wrote style file to " .. style_filepath)
end

-- ============================================================================
-- FILE OPERATIONS
-- ============================================================================

--- Update config from external file
---@param config_path string
---@return boolean success
function WaybarManager:update_config(config_path)
	if not Utils.file_exists(config_path) then
		Utils.error("Config file not found: " .. config_path)
		return false
	end

	local content, err = Utils.read_file(config_path)
	if err then
		Utils.error("Cannot read config: " .. err)
		return false
	end

	local config_dir = StateManager.CONFIG_JSONC:match("^(.*/)") 
	local success, mkdir_err = Utils.mkdir_p(config_dir)
	if not success then
		Utils.error("Cannot create config directory: " .. mkdir_err)
		return false
	end

	success, err = Utils.write_file(StateManager.CONFIG_JSONC, content)
	if not success then
		Utils.error("Cannot write config: " .. err)
		return false
	end

	Utils.info("Successfully copied config from " .. config_path)
	return true
end

--- Update style from external file
---@param style_path string
---@return boolean success
function WaybarManager:update_style(style_path)
	if not Utils.file_exists(style_path) then
		Utils.error("Style file not found: " .. style_path)
		return false
	end

	local config_dir = self.config_dir
	local user_style_filepath = config_dir .. "/user-style.css"
	local theme_style_filepath = config_dir .. "/theme.css"

	-- Ensure directory exists
	local success, mkdir_err = Utils.mkdir_p(config_dir)
	if not success then
		Utils.error("Cannot create config directory: " .. mkdir_err)
		return false
	end

	-- Create user-style.css if it doesn't exist
	if not Utils.file_exists(user_style_filepath) then
		local _, write_err = Utils.write_file(user_style_filepath, "/* User custom styles */\n")
		if write_err then
			Utils.warn("Cannot create user-style.css: " .. write_err)
		end
	end

	-- Check for theme.css
	if not Utils.file_exists(theme_style_filepath) then
		Utils.warn("Missing theme.css - please run 'hyde-shell reload' to generate it")
	end

	-- Write style.css with import
	self:write_style_file(style_path)

	-- Update state
	StateManager.set_state_value("WAYBAR_STYLE_PATH", style_path)

	-- Regenerate configuration
	self:update_icon_size()
	self:update_border_radius()
	self:generate_includes()
	self:update_global_css()

	Utils.info("Updated style from " .. style_path)
	self:restart_waybar()
	return true
end

-- ============================================================================
-- COMMAND HANDLERS
-- ============================================================================

--- Handle --next and --prev layout navigation
---@param direction string "next"|"prev"|nil
function WaybarManager:handle_layout_navigation(direction)
	local layouts_data = LayoutManager.list_layouts()
	local layout_list = {}

	for _, pair in ipairs(layouts_data.layouts) do
		if not pair.is_backup then
			table.insert(layout_list, pair.layout)
		end
	end

	local current_layout = StateManager.get_state_value("WAYBAR_LAYOUT_PATH")
	if not current_layout then
		Utils.error("Current layout not found")
		return
	end

	local current_index = nil
	for i, layout in ipairs(layout_list) do
		if layout == current_layout then
			current_index = i
			break
		end
	end

	if not current_index then
		Utils.warn("Current layout not in list, using first")
		current_index = 1
	end

	local new_index
	if direction == "next" then
		new_index = (current_index % #layout_list) + 1
	elseif direction == "prev" then
		new_index = ((current_index - 2) % #layout_list) + 1
	else
		return
	end

	self:set_layout(layout_list[new_index])
end

--- Set a specific layout
---@param layout string|nil
function WaybarManager:set_layout(layout)
	if not layout then
		Utils.error("No layout specified")
		return
	end

	local layouts_data = LayoutManager.list_layouts()
	local layout_path = nil
	local layout_name = nil
	local style_path = nil

	for _, pair in ipairs(layouts_data.layouts) do
		if pair.layout == layout or pair.name == layout then
			layout_path = pair.layout
			layout_name = pair.name
			style_path = pair.style
			break
		end
	end

	if not layout_path then
		Utils.error("Layout not found: " .. layout)
		return
	end

	-- Backup current if different
	if Utils.file_exists(StateManager.CONFIG_JSONC) then
		local current_hash, _ = Utils.get_file_hash(StateManager.CONFIG_JSONC)
		local layout_hash, _ = Utils.get_file_hash(layout_path)
		if current_hash and layout_hash and current_hash ~= layout_hash then
			local current_name = StateManager.get_state_value("WAYBAR_LAYOUT_NAME") or "unknown"
			LayoutManager.backup_layout(current_name)
		end
	end

	-- Apply layout
	if not LayoutManager.apply_layout(layout_path) then
		return
	end

	-- Update state
	StateManager.set_state_value("WAYBAR_LAYOUT_PATH", layout_path)
	StateManager.set_state_value("WAYBAR_LAYOUT_NAME", layout_name)
	StateManager.set_state_value("WAYBAR_STYLE_PATH", style_path)

	-- Update configuration
	self:write_style_file(style_path)
	self:update_icon_size()
	self:update_border_radius()
	self:generate_includes()
	self:update_global_css()

	Utils.info("Layout changed to " .. layout_name)
	self:restart_waybar()
end

--- Initialize waybar configuration
function WaybarManager:initialize()
	Utils.info("Initializing waybar configuration")

	StateManager.ensure_state_file()

	local current_layout = LayoutManager.get_current_layout()
	if current_layout then
		local style_path = LayoutManager.resolve_style_path(current_layout)
		LayoutManager.apply_layout(current_layout)
		self:write_style_file(style_path)
	else
		Utils.error("No layout found")
		return false
	end

	self:update_icon_size()
	self:update_border_radius()
	self:generate_includes()
	self:update_global_css()

	return true
end

-- ============================================================================
-- COMMAND LINE INTERFACE
-- ============================================================================

local function print_help()
	print([[
HyDE Waybar Configuration Manager (Lua)

Usage: waybar.lua [COMMAND] [OPTIONS]

Commands:
  --next, -n                 Switch to next layout
  --prev, -p                 Switch to previous layout
  --set LAYOUT              Set specific layout
  --update, -u              Update all configurations
  --update-icon-size, -i    Update icon sizes
  --update-border-radius, -b Update border radius
  --update-global-css, -g   Update global CSS
  --generate-includes, -G   Generate includes.json
  --config FILE, -c         Update from config file
  --style FILE, -s          Update from style file
  --json, -j                List layouts in JSON format
  --watch, -w               Watch and auto-restart waybar
  --kill, -k                Kill waybar
  --hide                    Toggle waybar hidden state
  --help, -h                Show this help message
]])
end

local function main()
	local manager = WaybarManager.new()

	-- Source environment files
	Utils.source_env_file(Utils.get_xdg_dir("runtime") .. "/hyde/environment")
	Utils.source_env_file(Utils.get_xdg_dir("state") .. "/hyde/config")

	-- Initialize if needed
	if not Utils.file_exists(StateManager.STATE_FILE) or
	   not Utils.file_exists(StateManager.CONFIG_JSONC) then
		manager:initialize()
	end

	-- Parse arguments
	local arg = arg or {}
	if #arg == 0 then
		manager:initialize()
		manager:restart_waybar()
		return
	end

	local cmd = arg[1]

	if cmd == "--help" or cmd == "-h" then
		print_help()
	elseif cmd == "--next" or cmd == "-n" then
		manager:handle_layout_navigation("next")
	elseif cmd == "--prev" or cmd == "-p" then
		manager:handle_layout_navigation("prev")
	elseif cmd == "--set" then
		manager:set_layout(arg[2])
	elseif cmd == "--config" or cmd == "-c" then
		if not arg[2] then
			Utils.error("Config file path required")
			os.exit(1)
		end
		manager:update_config(arg[2])
	elseif cmd == "--style" or cmd == "-s" then
		if not arg[2] then
			Utils.error("Style file path required")
			os.exit(1)
		end
		manager:update_style(arg[2])
	elseif cmd == "--update" or cmd == "-u" then
		manager:update_icon_size()
		manager:update_border_radius()
		manager:generate_includes()
		manager:update_global_css()
	elseif cmd == "--update-icon-size" or cmd == "-i" then
		manager:update_icon_size()
	elseif cmd == "--update-border-radius" or cmd == "-b" then
		manager:update_border_radius()
	elseif cmd == "--update-global-css" or cmd == "-g" then
		manager:update_global_css()
	elseif cmd == "--generate-includes" or cmd == "-G" then
		manager:generate_includes()
	elseif cmd == "--watch" or cmd == "-w" then
		manager:watch()
	elseif cmd == "--kill" or cmd == "-k" then
		manager:kill_waybar()
	elseif cmd == "--hide" then
		manager:send_signal_to_waybar("SIGUSR1")
	elseif cmd == "--json" or cmd == "-j" then
		local data = LayoutManager.list_layouts()
		print(Utils.json_encode(data))
	else
		print("Unknown command: " .. cmd)
		print_help()
		os.exit(1)
	end
end

-- Run if executed directly
if arg and arg[0] and arg[0]:find("waybar") then
	main()
end

return {
	WaybarManager = WaybarManager,
	StateManager = StateManager,
	LayoutManager = LayoutManager,
	Utils = Utils,
}
