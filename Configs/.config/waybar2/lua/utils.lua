-- Utility functions for waybar Lua configuration
-- Uses libuv for file operations and process management

local uv = require("luv") or require("luvit.uv")
local json = require("dkjson")

local Utils = {}

-- ============================================================================
-- LOGGING
-- ============================================================================

local LOG_LEVELS = { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 }
local CURRENT_LOG_LEVEL = LOG_LEVELS.INFO

function Utils.set_log_level(level_name)
	CURRENT_LOG_LEVEL = LOG_LEVELS[level_name:upper()] or LOG_LEVELS.INFO
end

local function log_message(level, level_name, message)
	if LOG_LEVELS[level_name] >= CURRENT_LOG_LEVEL then
		local timestamp = os.date("%Y-%m-%d %H:%M:%S")
		print(string.format("[%s] [%s] %s", timestamp, level_name, message))
	end
end

function Utils.debug(msg)
	log_message(LOG_LEVELS.DEBUG, "DEBUG", msg)
end

function Utils.info(msg)
	log_message(LOG_LEVELS.INFO, "INFO", msg)
end

function Utils.warn(msg)
	log_message(LOG_LEVELS.WARN, "WARN", msg)
end

function Utils.error(msg)
	log_message(LOG_LEVELS.ERROR, "ERROR", msg)
end

-- ============================================================================
-- FILE OPERATIONS WITH LIBUV
-- ============================================================================

--- Read file contents synchronously
---@param filepath string
---@return string|nil content, string|nil error
function Utils.read_file(filepath)
	local fd = uv.fs_open(filepath, "r", 0)
	if not fd then
		return nil, "Cannot open file: " .. filepath
	end

	local stat = uv.fs_stat(filepath)
	if not stat then
		uv.fs_close(fd)
		return nil, "Cannot stat file: " .. filepath
	end

	local content = uv.fs_read(fd, stat.size, 0)
	uv.fs_close(fd)

	return content, nil
end

--- Write file contents synchronously
---@param filepath string
---@param content string
---@return boolean success, string|nil error
function Utils.write_file(filepath, content)
	local fd = uv.fs_open(filepath, "w", 420)  -- 0644 in octal
	if not fd then
		return false, "Cannot open file for writing: " .. filepath
	end

	local written = uv.fs_write(fd, content, 0)
	uv.fs_close(fd)

	if not written then
		return false, "Failed to write file: " .. filepath
	end

	return true, nil
end

--- Append to file contents
---@param filepath string
---@param content string
---@return boolean success, string|nil error
function Utils.append_file(filepath, content)
	local fd = uv.fs_open(filepath, "a", 420)  -- 0644 in octal
	if not fd then
		return false, "Cannot open file for appending: " .. filepath
	end

	local written = uv.fs_write(fd, content, 0)
	uv.fs_close(fd)

	if not written then
		return false, "Failed to append to file: " .. filepath
	end

	return true, nil
end

--- Check if file exists
---@param filepath string
---@return boolean
function Utils.file_exists(filepath)
	local stat = uv.fs_stat(filepath)
	return stat ~= nil
end

--- Get file hash (SHA256) using libuv process
---@param filepath string
---@return string|nil hash, string|nil error
function Utils.get_file_hash(filepath)
	if not Utils.file_exists(filepath) then
		return nil, "File does not exist: " .. filepath
	end

	-- Use sha256sum command via libuv process spawn
	local result = ""
	local error_msg = ""

	local handle = uv.spawn("sha256sum", {
		args = { filepath },
		stdio = { nil, uv.new_pipe(false), uv.new_pipe(false) },
	}, function(code)
		if code ~= 0 then
			error_msg = "sha256sum failed with code: " .. code
		end
	end)

	if not handle then
		return nil, "Failed to spawn sha256sum"
	end

	-- Read stdout
	local stdout = handle.stdio[2]
	uv.read_start(stdout, function(err, data)
		if err then
			error_msg = err
		elseif data then
			result = result .. data
		end
	end)

	-- Wait for process completion
	uv.run("default")

	if error_msg ~= "" then
		return nil, error_msg
	end

	-- Extract hash (first field of output)
	local hash = result:match("^(%w+)")
	return hash, nil
end

--- Create directory recursively
---@param dirpath string
---@return boolean success, string|nil error
function Utils.mkdir_p(dirpath)
	local parts = {}
	for part in dirpath:gmatch("[^/]+") do
		table.insert(parts, part)
	end

	local current = ""
	if dirpath:sub(1, 1) == "/" then
		current = "/"
	end

	for _, part in ipairs(parts) do
		current = current == "/" and "/" .. part or current .. "/" .. part

		if not Utils.file_exists(current) then
			local ok = uv.fs_mkdir(current, 493)  -- 0755 in octal
			if not ok then
				return false, "Failed to create directory: " .. current
			end
		end
	end

	return true, nil
end

--- List files in directory recursively
---@param dirpath string
---@param pattern string|nil
---@param recursive boolean
---@return table files
function Utils.list_files(dirpath, pattern, recursive)
	recursive = recursive ~= false  -- default true
	pattern = pattern or ".*"

	local files = {}
	local function scan_dir(path)
		local scan = uv.fs_scandir(path)
		if not scan then
			return
		end

		while true do
			local name, type = uv.fs_scandir_next(scan)
			if not name then
				break
			end

			local fullpath = path .. "/" .. name
			if type == "file" and name:match(pattern) then
				table.insert(files, fullpath)
			elseif type == "directory" and recursive and name ~= "backup" then
				scan_dir(fullpath)
			end
		end
	end

	scan_dir(dirpath)
	return files
end

-- ============================================================================
-- PROCESS MANAGEMENT WITH LIBUV
-- ============================================================================

--- Run command synchronously and capture output
---@param cmd string
---@param args table
---@param options table
---@return string output, string error, integer exit_code
function Utils.run_command(cmd, args, options)
	args = args or {}
	options = options or {}

	local output = ""
	local error_output = ""
	local exit_code = 0

	local stdio = {}
	if options.capture_stdout ~= false then
		stdio[2] = uv.new_pipe(false)
	end
	if options.capture_stderr ~= false then
		stdio[3] = uv.new_pipe(false)
	end

	local handle = uv.spawn(cmd, {
		args = args,
		stdio = stdio,
		cwd = options.cwd,
		env = options.env,
	}, function(code, signal)
		exit_code = code or 0
	end)

	if not handle then
		return "", "Failed to spawn process: " .. cmd, 127
	end

	-- Read stdout
	if stdio[2] then
		uv.read_start(stdio[2], function(err, data)
			if err then
				error_output = error_output .. "stdout error: " .. err .. "\n"
			elseif data then
				output = output .. data
			end
		end)
	end

	-- Read stderr
	if stdio[3] then
		uv.read_start(stdio[3], function(err, data)
			if err then
				error_output = error_output .. "stderr error: " .. err .. "\n"
			elseif data then
				error_output = error_output .. data
			end
		end)
	end

	-- Run event loop
	uv.run()

	return output, error_output, exit_code
end

--- Check if process is running
---@param process_name string
---@return boolean
function Utils.process_running(process_name)
	local output, _, code = Utils.run_command("pgrep", { "-x", process_name })
	return code == 0 and output:match("%d+") ~= nil
end

--- Kill process by name
---@param process_name string
---@param signal number
---@return boolean success
function Utils.kill_process(process_name, signal)
	signal = signal or 15  -- SIGTERM
	local output, _, code = Utils.run_command("pkill", { "-" .. signal, "-x", process_name })
	return code == 0
end

--- Execute command without waiting for output (async)
---@param cmd string
---@param args table
---@param callback function|nil
function Utils.spawn_async(cmd, args, callback)
	args = args or {}
	local handle = uv.spawn(cmd, { args = args }, callback or function() end)
	return handle
end

-- ============================================================================
-- JSON OPERATIONS
-- ============================================================================

--- Decode JSON string
---@param json_str string
---@return table|nil data, string|nil error
function Utils.json_decode(json_str)
	local data, err = json.decode(json_str)
	if err then
		return nil, err
	end
	return data, nil
end

--- Encode table as JSON
---@param data table
---@return string json_str
function Utils.json_encode(data)
	return json.encode(data)
end

--- Load JSON file
---@param filepath string
---@return table|nil data, string|nil error
function Utils.json_load(filepath)
	local content, err = Utils.read_file(filepath)
	if err then
		return nil, err
	end
	return Utils.json_decode(content)
end

--- Save JSON file
---@param filepath string
---@param data table
---@return boolean success, string|nil error
function Utils.json_save(filepath, data)
	local json_str = Utils.json_encode(data)
	return Utils.write_file(filepath, json_str)
end

-- ============================================================================
-- STRING OPERATIONS
-- ============================================================================

--- Trim whitespace from string
---@param str string
---@return string
function Utils.trim(str)
	return str:match("^%s*(.-)%s*$")
end

--- Split string by delimiter
---@param str string
---@param delim string
---@return table parts
function Utils.split(str, delim)
	local parts = {}
	for part in str:gmatch("[^" .. delim .. "]+") do
		table.insert(parts, part)
	end
	return parts
end

--- Check if string starts with prefix
---@param str string
---@param prefix string
---@return boolean
function Utils.starts_with(str, prefix)
	return str:sub(1, #prefix) == prefix
end

--- Check if string ends with suffix
---@param str string
---@param suffix string
---@return boolean
function Utils.ends_with(str, suffix)
	return str:sub(-#suffix) == suffix
end

-- ============================================================================
-- ENVIRONMENT VARIABLES
-- ============================================================================

--- Get XDG directory path
---@param dir_type string "config"|"data"|"cache"|"state"|"runtime"
---@return string path
function Utils.get_xdg_dir(dir_type)
	if dir_type == "config" then
		return os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
	elseif dir_type == "data" then
		return os.getenv("XDG_DATA_HOME") or (os.getenv("HOME") .. "/.local/share")
	elseif dir_type == "cache" then
		return os.getenv("XDG_CACHE_HOME") or (os.getenv("HOME") .. "/.cache")
	elseif dir_type == "state" then
		return os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")
	elseif dir_type == "runtime" then
		return os.getenv("XDG_RUNTIME_DIR") or ("/run/user/" .. os.getenv("UID"))
	end
	return ""
end

--- Source environment variables from file
---@param filepath string
---@return table env_vars
function Utils.source_env_file(filepath)
	local env_vars = {}
	local content, err = Utils.read_file(filepath)

	if err then
		Utils.debug("Could not read env file: " .. filepath)
		return env_vars
	end

	for line in content:gmatch("[^\n]+") do
		line = Utils.trim(line)
		if line ~= "" and not Utils.starts_with(line, "#") then
			local key, value = line:match("^([^=]+)=(.*)$")
			if key then
				-- Remove quotes from value
				value = value:match('^"(.*)"$') or value:match("^'(.*)'$") or value
				env_vars[key] = value
				os.environ[key] = value
			end
		end
	end

	return env_vars
end

-- ============================================================================
-- TABLE OPERATIONS
-- ============================================================================

--- Deep copy a table
---@param tbl table
---@return table copy
function Utils.deep_copy(tbl)
	local copy = {}
	for k, v in pairs(tbl) do
		if type(v) == "table" then
			copy[k] = Utils.deep_copy(v)
		else
			copy[k] = v
		end
	end
	return copy
end

--- Merge two tables
---@param t1 table
---@param t2 table
---@return table merged
function Utils.merge_tables(t1, t2)
	local merged = Utils.deep_copy(t1)
	for k, v in pairs(t2) do
		if type(v) == "table" and type(merged[k]) == "table" then
			merged[k] = Utils.merge_tables(merged[k], v)
		else
			merged[k] = v
		end
	end
	return merged
end

return Utils
