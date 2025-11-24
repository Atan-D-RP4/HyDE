-- Layout and style management for waybar
-- Handles layout discovery, style resolution, and file operations

local Utils = require("utils")
local StateManager = require("state_manager")

local LayoutManager = {}
LayoutManager.__index = LayoutManager

-- Configuration paths
local XDG_CONFIG_HOME = Utils.get_xdg_dir("config")
local XDG_DATA_HOME = Utils.get_xdg_dir("data")

LayoutManager.LAYOUT_DIRS = {
	XDG_CONFIG_HOME .. "/waybar/layouts",
	XDG_DATA_HOME .. "/waybar/layouts",
	"/usr/local/share/waybar/layouts",
	"/usr/share/waybar/layouts",
}

LayoutManager.STYLE_DIRS = {
	XDG_CONFIG_HOME .. "/waybar/styles",
	XDG_DATA_HOME .. "/waybar/styles",
}

LayoutManager.MODULE_DIRS = {
	XDG_CONFIG_HOME .. "/waybar/modules",
	XDG_DATA_HOME .. "/waybar/modules",
	"/usr/local/share/waybar/modules",
	"/usr/share/waybar/modules",
}

LayoutManager.LAYOUT_IGNORE = { "test.jsonc", "dock#sample.jsonc" }

-- ============================================================================
-- LAYOUT DISCOVERY
-- ============================================================================

--- Find all layout files recursively
---@return table layouts
function LayoutManager.find_layout_files()
	local layouts = {}
	for _, layout_dir in ipairs(LayoutManager.LAYOUT_DIRS) do
		if Utils.file_exists(layout_dir) then
			local files = Utils.list_files(layout_dir, "%.jsonc$", true)
			for _, file in ipairs(files) do
				local basename = file:match("([^/]+)$")
				local ignored = false
				for _, ignore_pattern in ipairs(LayoutManager.LAYOUT_IGNORE) do
					if basename == ignore_pattern then
						ignored = true
						break
					end
				end
				if not ignored then
					table.insert(layouts, file)
				end
			end
		end
	end
	table.sort(layouts)
	return layouts
end

--- Find current layout from state or config hash comparison
---@return string|nil layout_path
function LayoutManager.get_current_layout()
	Utils.debug("Getting current layout")

	-- Try to get from state file first
	local layout_path = StateManager.get_state_value("WAYBAR_LAYOUT_PATH")
	if layout_path and Utils.file_exists(layout_path) then
		Utils.debug("Found current layout in state file: " .. layout_path)
		return layout_path
	end

	-- Try to get by name
	local layout_name = StateManager.get_state_value("WAYBAR_LAYOUT_NAME")
	if layout_name then
		local layouts = LayoutManager.find_layout_files()
		for _, layout in ipairs(layouts) do
			local name = layout:gsub("%.jsonc$", ""):match("([^/]+)$")
			if name == layout_name then
				Utils.debug("Found current layout by name in state file: " .. layout)
				return layout
			end
		end
	end

	-- Hash comparison fallback
	Utils.debug("Fallback to hash comparison method")
	local config_path = StateManager.CONFIG_JSONC
	local layouts = LayoutManager.find_layout_files()

	if #layouts == 0 then
		Utils.error("No layout files found")
		return nil
	end

	if not Utils.file_exists(config_path) then
		Utils.debug("Config file not found, using first layout")
		local layout = layouts[1]
		local name = layout:gsub("%.jsonc$", ""):match("([^/]+)$")
		StateManager.set_state_value("WAYBAR_LAYOUT_PATH", layout)
		StateManager.set_state_value("WAYBAR_LAYOUT_NAME", name)
		return layout
	end

	-- Try hash matching
	local config_hash, _ = Utils.get_file_hash(config_path)
	if config_hash then
		for _, layout_file in ipairs(layouts) do
			local layout_hash, _ = Utils.get_file_hash(layout_file)
			if layout_hash == config_hash then
				Utils.debug("Found layout by hash: " .. layout_file)
				local name = layout_file:gsub("%.jsonc$", ""):match("([^/]+)$")
				StateManager.set_state_value("WAYBAR_LAYOUT_PATH", layout_file)
				StateManager.set_state_value("WAYBAR_LAYOUT_NAME", name)
				return layout_file
			end
		end
	end

	-- Fallback to first layout
	Utils.debug("No matching layout found, using first layout")
	local layout = layouts[1]
	local name = layout:gsub("%.jsonc$", ""):match("([^/]+)$")
	StateManager.set_state_value("WAYBAR_LAYOUT_PATH", layout)
	StateManager.set_state_value("WAYBAR_LAYOUT_NAME", name)
	return layout
end

-- ============================================================================
-- STYLE RESOLUTION
-- ============================================================================

--- Resolve style path based on layout
---@param layout_path string
---@return string style_path
function LayoutManager.resolve_style_path(layout_path)
	local basename = layout_path:match("([^/]+)$"):gsub("%.jsonc$", "")
	local dirname = layout_path:match("([^/]+)/[^/]+$") or ""

	-- Try exact name match
	for _, style_dir in ipairs(LayoutManager.STYLE_DIRS) do
		if Utils.file_exists(style_dir) then
			local files = Utils.list_files(style_dir, "^" .. basename .. ".*%.css$", false)
			if #files > 0 then
				Utils.debug("Resolved style: " .. files[1])
				return files[1]
			end
		end
	end

	-- Try name without hash
	local name_without_hash = basename:match("([^#]+)") or basename
	for _, style_dir in ipairs(LayoutManager.STYLE_DIRS) do
		if Utils.file_exists(style_dir) then
			local files = Utils.list_files(style_dir, "^" .. name_without_hash .. ".*%.css$", false)
			if #files > 0 then
				Utils.debug("Resolved style with hash removal: " .. files[1])
				return files[1]
			end
		end
	end

	-- Try directory name
	if dirname ~= "" then
		for _, style_dir in ipairs(LayoutManager.STYLE_DIRS) do
			if Utils.file_exists(style_dir) then
				local files = Utils.list_files(style_dir, "^" .. dirname .. ".*%.css$", false)
				if #files > 0 then
					Utils.debug("Resolved style from dir name: " .. files[1])
					return files[1]
				end
			end
		end
	end

	-- Try default
	for _, style_dir in ipairs(LayoutManager.STYLE_DIRS) do
		if Utils.file_exists(style_dir .. "/defaults.css") then
			Utils.debug("Using default style")
			return style_dir .. "/defaults.css"
		end
	end

	Utils.warn("No style found, returning fallback")
	return LayoutManager.STYLE_DIRS[1] .. "/defaults.css"
end

-- ============================================================================
-- LAYOUT LISTING
-- ============================================================================

--- List all layouts with their styles
---@return table layout_data
function LayoutManager.list_layouts()
	local layouts = LayoutManager.find_layout_files()
	local layout_style_pairs = {}
	local backup_layouts = {}

	for _, layout in ipairs(layouts) do
		-- Check if it's a backup
		if layout:find("/backup/") or layout:find("\\backup\\") then
			local name = layout:gsub("%.jsonc$", "")
			table.insert(backup_layouts, { layout = layout, name = name })
		else
			local name = layout:gsub("%.jsonc$", ""):match("([^/]+)$")
			local style = LayoutManager.resolve_style_path(layout)
			table.insert(layout_style_pairs, { layout = layout, name = name, style = style })
		end
	end

	-- Add backup entry if backups exist
	if #backup_layouts > 0 then
		table.insert(layout_style_pairs, {
			name = "List all " .. tostring(#backup_layouts) .. " Backup(s)",
			style = "",
			layout = "",
			is_backup = true,
		})
	end

	return { layouts = layout_style_pairs, backups = backup_layouts }
end

-- ============================================================================
-- LAYOUT OPERATIONS
-- ============================================================================

--- Copy layout file to config
---@param layout_path string
---@return boolean success
function LayoutManager.apply_layout(layout_path)
	if not Utils.file_exists(layout_path) then
		Utils.error("Layout file not found: " .. layout_path)
		return false
	end

	local content, err = Utils.read_file(layout_path)
	if err then
		Utils.error("Cannot read layout: " .. err)
		return false
	end

	-- Ensure config directory exists
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

	Utils.debug("Applied layout to config")
	return true
end

--- Backup current layout
---@param layout_name string
---@return string|nil backup_path
function LayoutManager.backup_layout(layout_name)
	if not Utils.file_exists(StateManager.CONFIG_JSONC) then
		Utils.debug("No config to backup")
		return nil
	end

	local config_dir = StateManager.CONFIG_JSONC:match("^(.*/)")
	local backup_dir = config_dir .. "layouts/backup"

	local success, err = Utils.mkdir_p(backup_dir)
	if not success then
		Utils.error("Cannot create backup directory: " .. err)
		return nil
	end

	local timestamp = os.date("%Y%m%d_%H%M%S")
	local backup_filename = layout_name .. "_" .. timestamp .. ".jsonc"
	local backup_path = backup_dir .. "/" .. backup_filename

	local content, read_err = Utils.read_file(StateManager.CONFIG_JSONC)
	if read_err then
		Utils.error("Cannot read config for backup: " .. read_err)
		return nil
	end

	success, err = Utils.write_file(backup_path, content)
	if not success then
		Utils.error("Cannot write backup: " .. err)
		return nil
	end

	Utils.debug("Created backup at: " .. backup_path)
	return backup_path
end

return LayoutManager
