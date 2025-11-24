-- State and configuration file management for waybar
-- Handles state persistence, config value retrieval, and caching

local Utils = require("utils")

local StateManager = {}
StateManager.__index = StateManager

-- Paths
local XDG_CONFIG_HOME = Utils.get_xdg_dir("config")
local XDG_STATE_HOME = Utils.get_xdg_dir("state")
local XDG_DATA_HOME = Utils.get_xdg_dir("data")

StateManager.STATE_FILE = XDG_STATE_HOME .. "/hyde/staterc"
StateManager.HYDE_CONFIG = XDG_STATE_HOME .. "/hyde/config"
StateManager.CONFIG_JSONC = XDG_CONFIG_HOME .. "/waybar/config.jsonc"

-- ============================================================================
-- STATE FILE OPERATIONS
-- ============================================================================

--- Read value from state file
---@param key string
---@param default string|nil
---@return string|nil value
function StateManager.get_state_value(key, default)
	if not Utils.file_exists(StateManager.STATE_FILE) then
		return default
	end

	local content, err = Utils.read_file(StateManager.STATE_FILE)
	if err then
		Utils.error("Cannot read state file: " .. err)
		return default
	end

	for line in content:gmatch("[^\n]+") do
		if Utils.starts_with(line, key .. "=") then
			local value = line:sub(#key + 2)
			return Utils.trim(value)
		end
	end

	return default
end

--- Write value to state file
---@param key string
---@param value string
---@return boolean success, string|nil error
function StateManager.set_state_value(key, value)
	-- Ensure directory exists
	local success, err = Utils.mkdir_p(Utils.split(StateManager.STATE_FILE, "/")[#Utils.split(StateManager.STATE_FILE, "/") - 1])
	if not success then
		return false, err
	end

	local existing_lines = {}
	local seen_keys = {}

	if Utils.file_exists(StateManager.STATE_FILE) then
		local content, read_err = Utils.read_file(StateManager.STATE_FILE)
		if read_err then
			return false, read_err
		end

		for line in content:gmatch("[^\n]+") do
			line = Utils.trim(line)
			if line ~= "" then
				local current_key = line:match("^([^=]+)=")
				if current_key then
					if current_key ~= key and not seen_keys[current_key] then
						table.insert(existing_lines, line)
						seen_keys[current_key] = true
					end
				else
					table.insert(existing_lines, line)
				end
			end
		end
	end

	table.insert(existing_lines, key .. "=" .. value)

	local file_content = table.concat(existing_lines, "\n") .. "\n"
	return Utils.write_file(StateManager.STATE_FILE, file_content)
end

--- Delete value from state file
---@param key string
---@return boolean success
function StateManager.delete_state_value(key)
	if not Utils.file_exists(StateManager.STATE_FILE) then
		return true
	end

	local content, err = Utils.read_file(StateManager.STATE_FILE)
	if err then
		return false
	end

	local lines = {}
	for line in content:gmatch("[^\n]+") do
		line = Utils.trim(line)
		if line ~= "" and not Utils.starts_with(line, key .. "=") then
			table.insert(lines, line)
		end
	end

	if #lines == 0 then
		return true
	end

	local file_content = table.concat(lines, "\n") .. "\n"
	return Utils.write_file(StateManager.STATE_FILE, file_content)
end

-- ============================================================================
-- CONFIG FILE OPERATIONS
-- ============================================================================

--- Get value from hyde config
---@param key string
---@param default string|nil
---@return string|nil value
function StateManager.get_config_value(key, default)
	if not Utils.file_exists(StateManager.HYDE_CONFIG) then
		return default
	end

	local content, err = Utils.read_file(StateManager.HYDE_CONFIG)
	if err then
		Utils.error("Cannot read config file: " .. err)
		return default
	end

	for line in content:gmatch("[^\n]+") do
		line = Utils.trim(line)
		-- Handle "export " prefix
		if Utils.starts_with(line, "export ") then
			line = line:sub(8)  -- Remove "export "
		end

		if Utils.starts_with(line, key .. "=") then
			local value = line:sub(#key + 2)
			return Utils.trim(value)
		end
	end

	return default
end

-- ============================================================================
-- STATE FILE INITIALIZATION
-- ============================================================================

--- Ensure state file exists with necessary entries
---@return boolean success
function StateManager.ensure_state_file()
	-- Create directory
	local dir = Utils.split(StateManager.STATE_FILE, "/")
	table.remove(dir)
	local dir_path = "/" .. table.concat(dir, "/")

	local success, err = Utils.mkdir_p(dir_path)
	if not success then
		Utils.error("Cannot create state directory: " .. err)
		return false
	end

	Utils.debug("Ensuring state file exists at: " .. StateManager.STATE_FILE)

	if not Utils.file_exists(StateManager.STATE_FILE) then
		Utils.debug("State file does not exist, will be created on first write")
		return true
	end

	local content, err = Utils.read_file(StateManager.STATE_FILE)
	if err then
		Utils.error("Cannot read state file: " .. err)
		return false
	end

	-- Check for required keys
	local has_layout_path = content:find("WAYBAR_LAYOUT_PATH=") ~= nil
	local has_layout_name = content:find("WAYBAR_LAYOUT_NAME=") ~= nil
	local has_style_path = content:find("WAYBAR_STYLE_PATH=") ~= nil

	if has_layout_path and has_layout_name and has_style_path then
		Utils.debug("State file has all required entries")
		return true
	end

	Utils.debug("State file is missing entries, needs update")
	return true
end

-- ============================================================================
-- BATCH OPERATIONS
-- ============================================================================

--- Get multiple state values
---@param keys table
---@return table values
function StateManager.get_state_values(keys)
	local values = {}
	for _, key in ipairs(keys) do
		values[key] = StateManager.get_state_value(key)
	end
	return values
end

--- Set multiple state values
---@param updates table
---@return boolean success
function StateManager.set_state_values(updates)
	for key, value in pairs(updates) do
		local success, err = StateManager.set_state_value(key, value)
		if not success then
			Utils.error("Failed to set " .. key .. ": " .. (err or "unknown error"))
			return false
		end
	end
	return true
end

-- ============================================================================
-- HELPERS
-- ============================================================================

--- Get or create a value with a fallback
---@param key string
---@param default string
---@param auto_set boolean
---@return string value
function StateManager.get_or_create(key, default, auto_set)
	local value = StateManager.get_state_value(key)
	if value == nil then
		value = default
		if auto_set then
			StateManager.set_state_value(key, value)
		end
	end
	return value
end

return StateManager
