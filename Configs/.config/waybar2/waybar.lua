#!/usr/bin/env lua5.1

local json = require("dkjson")

-- Dynamically set package.path to include ~/.config/waybar/lua/
local conf_dir = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
local lua_module_path = conf_dir .. "/waybar/lua/?.lua"
package.path = lua_module_path .. ";" .. package.path

-- Waybar Config Builder
local WaybarBuilder = {}
WaybarBuilder.__index = WaybarBuilder

-- Module definitions
local modules = require("wb_modules")

-- Preset configurations
local presets = require("wb_presets")

-- Theme configurations
local themes = {
	default = {
		layer = "top",
		position = "top",
		height = 30,
		spacing = 4,
		margin_top = 0,
		margin_bottom = 0,
		margin_left = 0,
		margin_right = 0,
	},
}

-- Function to create a WaybarBuilder from a preset
---@param preset table
function WaybarBuilder:from_preset(preset)
	if not preset then
		error("No preset provided")
	end

	local builder = WaybarBuilder:new("default")

	-- Set position
	builder:set_position(preset.position)

	-- Set height if provided, otherwise keep default
	if preset.height then
		builder:set_height(preset.height)
	end

	-- Add padding modules and cleaned module lists
	builder
		:add_mod("left", preset.modules_left)
		:add_mod("center", preset.modules_center)
		:add_mod("right", preset.modules_right)

	return builder
end

-- Constructor
function WaybarBuilder:new(theme_name)
	local obj = {
		config = {},
		theme = themes[theme_name] or themes.default,
		modules_left = {},
		modules_center = {},
		modules_right = {},
		custom_modules = {},
		variables = {
			w_position = "top",
			hv_pos = "height",
			r_deg = 0,
			w_height = 30,
			i_size = 16,
			i_theme = "default",
			i_task = 16,
			i_priv = 12,
			set_sysname = os.getenv("HOSTNAME") or "localhost",
			WAYBAR_OUTPUT = { "*" },
		},
	}
	setmetatable(obj, self)
	return obj
end

-- Fluent interface methods
function WaybarBuilder:set_position(position)
	self.variables.w_position = position
	if position == "left" then
		self.variables.hv_pos = "width"
		self.variables.r_deg = 90
	elseif position == "right" then
		self.variables.hv_pos = "width"
		self.variables.r_deg = 270
	else
		self.variables.hv_pos = "height"
		self.variables.r_deg = 0
	end
	return self
end

function WaybarBuilder:set_height(height)
	self.variables.w_height = height
	self.variables.i_size = math.max(12, math.floor(height * 6 / 10))
	self.variables.i_task = math.max(16, math.floor(height * 6 / 10))
	self.variables.i_priv = math.max(12, math.floor(height * 6 / 13))
	return self
end

function WaybarBuilder:set_output(outputs)
	self.variables.w_output = outputs
	return self
end

---@param pos string
---@param module_names table
function WaybarBuilder:add_mod(pos, module_names)
	local mod_pos = {}
	table.insert(mod_pos, "custom/padd")
	for _, module in ipairs(module_names) do
		if type(module) == "string" then
			table.insert(mod_pos, "custom/l_end")
			table.insert(mod_pos, module)
			table.insert(mod_pos, "custom/r_end")
		elseif type(module) == "table" then
			table.insert(mod_pos, "custom/l_end")
			for _, name in ipairs(module) do
				table.insert(mod_pos, name)
			end
			table.insert(mod_pos, "custom/r_end")
		end
	end
	table.insert(mod_pos, "custom/padd")
	if pos == "left" then
		self.modules_left = mod_pos
	elseif pos == "center" then
		self.modules_center = mod_pos
	elseif pos == "right" then
		self.modules_right = mod_pos
	else
		error("Invalid position: " .. tostring(pos))
	end
	return self
end

function WaybarBuilder:add_custom_module(name, config_func)
	self.custom_modules[name] = config_func
	return self
end

-- Collect all used modules
function WaybarBuilder:get_used_modules()
	local used = {}
	local all_modules = {}
	for _, name in ipairs(self.modules_left) do
		table.insert(all_modules, name)
	end
	for _, name in ipairs(self.modules_center) do
		table.insert(all_modules, name)
	end
	for _, name in ipairs(self.modules_right) do
		table.insert(all_modules, name)
	end
	for _, name in ipairs(all_modules) do
		if not used[name] then
			if modules[name] then
				used[name] = modules[name](self)
			elseif self.custom_modules[name] then
				used[name] = self.custom_modules[name](self)
			end
		end
	end
	return used
end

-- Build final configuration
function WaybarBuilder:build()
	local config = {
		layer = "top",
		output = self.variables.w_output,
		position = self.variables.w_position,
		mod = "dock",
		[self.variables.hv_pos] = self.variables.w_height,
		exclusive = true,
		passthrough = false,
		["gtk-layer-shell"] = true,
		["reload_style_on_change"] = true,
	}
	if #self.modules_left > 0 then
		config["modules-left"] = self.modules_left
	end
	if #self.modules_center > 0 then
		config["modules-center"] = self.modules_center
	end
	if #self.modules_right > 0 then
		config["modules-right"] = self.modules_right
	end
	local used_modules = self:get_used_modules()
	for name, module_config in pairs(used_modules) do
		config[name] = module_config
	end
	return config
end

function WaybarBuilder:generate_style()
	-- Set environment variables that wbstylegen.sh expects
	local env_vars = self.variables

	-- Build environment string for the command
	local env_string = ""
	for key, value in pairs(env_vars) do
		vim.print(value)
		env_string = env_string .. key .. "=" .. string:format(value) .. " "
	end
	vim.print("Environment variables for style generation: " .. env_string)

	-- Get script directory (assuming it's in the same location as wbarconfgen.sh)
	local script_dir = os.getenv("HOME") .. "/.local/lib/hyde"
	local style_script = script_dir .. "/wbarstylegen.sh"

	-- Execute wbarstylegen.sh with environment variables
	local command = env_string .. style_script
	local success = os.execute(command)

	if success == 0 then
		print("Style generation completed successfully")
		return true
	else
		print("Error: Style generation failed")
		return false
	end
end

function WaybarBuilder:to_json()
	return json.encode(self:build())
end

-- Example usage
local function main(preset_file, config_file, waybar_proc)
	-- If waybar is already running, terminate it
	local handle = io.popen("pgrep -x waybar", "r")
	if handle == nil then
		print("Error: Could not check if Waybar is running.")
		return
	end
	local pid = handle:read("*n")
	handle:close()

	if pid then
		os.execute("kill -9 " .. pid)
		if arg[1] ~= "next" and arg[1] ~= "prev" then
			print("Waybar was running, it has been terminated.")
			return
		end
	end

	local preset_incr = arg[1] == "next" and 1 or (arg[1] == "prev" and -1 or 0)

	-- Ensure preset file exists
	if not io.open("/tmp/waybar_preset", "r") then
		local f = io.open("/tmp/waybar_preset", "w")
		if not f then
			print("Error: Could not create /tmp/waybar_preset")
			return
		end
		f:write("0")
		f:close()
	end

	-- Open preset file
	preset_file = io.open("/tmp/waybar_preset", "r")
	if not preset_file then
		print("Error: Could not open /tmp/waybar_preset for reading.")
		return
	end

	-- Read preset index
	local preset_idx = tonumber(preset_file:read("*n"))
	if not preset_idx or preset_idx < 0 or preset_idx >= #presets then
		print("Error: Invalid preset index in /tmp/waybar_preset")
		preset_file:close()
		return
	end

	preset_idx = (preset_idx + preset_incr) % #presets

	-- Close preset file before writing to avoid conflicts
	preset_file:close()
	preset_file = nil

	-- Create builder from preset
	local preset = presets[preset_idx + 1] -- Lua tables are 1-indexed
	if not preset then
		print("Error: Preset index " .. preset_idx .. " not found.")
		return
	end
	local builder = WaybarBuilder:from_preset(preset)
	local conf = builder:to_json()

	-- Write configuration file
	local config_dir = os.getenv("XDG_CONFIG_HOME") or os.getenv("HOME") .. "/.config"
	config_file = io.open(config_dir .. "/waybar/config.jsonc", "w")
	if not config_file then
		print("Error: Could not open " .. config_file .. " for writing.")
		return
	end
	config_file:write(conf)
	config_file:close()
	-- Write updated preset index
	preset_file = io.open("/tmp/waybar_preset", "w")
	if not preset_file then
		print("Error: Could not open /tmp/waybar_preset for writing.")
		return
	end
	preset_file:write(tostring(preset_idx))
	preset_file:close()

	-- Start Waybar
	waybar_proc = io.popen("stdbuf -oL waybar 2>/dev/null", "r")
	if not waybar_proc then
		print("Error: Could not start Waybar with the new configuration.")
		return
	end
end

local function cleanup(preset_file, config_file, waybar_proc)
	if preset_file then
		preset_file:close()
	end
	if config_file then
		config_file:close()
	end
	if waybar_proc then
		waybar_proc:close()
	end
end

if arg and arg[0] and arg[0]:match("waybar.*%.lua$") then
	local preset_file = nil
	local config_file = nil
	local waybar_proc = nil
	local success, err = pcall(main, preset_file, config_file, waybar_proc)
	if not success then
		print("ERROR: " .. tostring(err))
		cleanup(preset_file, config_file, waybar_proc)
		os.exit(1)
	end
end

local builder = WaybarBuilder:from_preset(require("wb_presets")[2])
builder:generate_style()
vim.print(builder)

return {
	WaybarBuilder = WaybarBuilder,
	modules = modules,
	themes = themes,
}
