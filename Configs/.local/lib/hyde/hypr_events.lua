#!/usr/bin/env luajit

package.path = package.path .. ";/usr/share/lua/5.1/?.lua;/usr/share/lua/5.1/?/init.lua"
package.path = package.path .. ";/usr/share/lua/5.2/?.lua;/usr/share/lua/5.2/?/init.lua"

-- Load dkjson module
local dkjson = require("dkjson")
-- Debug: print available dkjson fields
-- (optional, remove in production)
for k, v in pairs(dkjson) do
	print("dkjson field:", k, v)
end

-- Load luv
package.cpath = package.cpath .. ";/usr/lib/lib?.so"
local uv = require("luv")

-- Get IPC socket paths
local runtime = os.getenv("XDG_RUNTIME_DIR")
local sig = os.getenv("HYPRLAND_INSTANCE_SIGNATURE")
if not runtime or not sig then
	error("XDG_RUNTIME_DIR or HYPRLAND_INSTANCE_SIGNATURE not set")
end

local cmd_sockpath = runtime .. "/hypr/" .. sig .. "/.socket.sock"
local evt_sockpath = runtime .. "/hypr/" .. sig .. "/.socket2.sock"

-- Event dispatcher (with wildcard/list matching)
local Event = {}
Event.__index = Event

function Event:new()
	return setmetatable({ listeners = {} }, self)
end

function Event:on(event_name, callback)
	if type(event_name) == "table" then
		for _, ev in ipairs(event_name) do
			self:on(ev, callback)
		end
	else
		self.listeners[event_name] = self.listeners[event_name] or {}
		table.insert(self.listeners[event_name], callback)
	end
end

function Event:off(event_name, callback)
	if type(event_name) == "table" then
		for _, ev in ipairs(event_name) do
			self:off(ev, callback)
		end
	else
		local list = self.listeners[event_name]
		if not list then
			return
		end
		for i = #list, 1, -1 do
			if list[i] == callback then
				table.remove(list, i)
			end
		end
	end
end

function Event:emit(event_name, ...)
	-- specific
	local list = self.listeners[event_name]
	if list then
		for _, cb in ipairs(list) do
			local ok, err = pcall(cb, ...)
			if not ok then
				io.stderr:write(("Error in callback for event '%s': %s\n"):format(event_name, err))
			end
		end
	end
	-- wildcard
	local wc = self.listeners["*"]
	if wc then
		for _, cb in ipairs(wc) do
			local ok, err = pcall(cb, event_name, ...)
			if not ok then
				io.stderr:write(("Error in wildcard callback for '%s': %s\n"):format(event_name, err))
			end
		end
	end
end

local dispatcher = Event:new()

local function hypr_autocmd(event_names, callback)
	dispatcher:on(event_names, callback)
end

-- Send Hyprland command via IPC socket
local function send_hypr_command(cmd, callback)
	-- Create pipe for socket
	local pipe = uv.new_pipe(false)

	-- Connect to command socket
	uv.pipe_connect(pipe, cmd_sockpath, function(err)
		if err then
			return callback(false, "connect error: " .. tostring(err))
		end

		-- After connecting, write the command
		-- According to IPC spec, no trailing newline or with care
		pipe:write(cmd, function(write_err)
			if write_err then
				pipe:close()
				return callback(false, "write error: " .. tostring(write_err))
			end

			-- Now read the response
			local response = ""
			uv.read_start(pipe, function(read_err, chunk)
				if read_err then
					pipe:close()
					return callback(false, "read error: " .. tostring(read_err))
				end

				if chunk then
					response = response .. chunk
				else
					-- EOF: stop and return
					pipe:read_stop()
					pipe:close()
					callback(true, response)
				end
			end)
		end)
	end)
end

-- Sync input devices (using IPC + dkjson)
local function sync_device_input()
	-- Use IPC to query devices
	-- e.g., "j/devices" to get JSON
	send_hypr_command("j/devices", function(ok, resp)
		if not ok then
			io.stderr:write("sync_device_input: error querying devices: ", resp, "\n")
			return
		end

		-- Parse JSON
		local parsed, pos, err = dkjson.decode(resp, 1, nil)
		if err then
			io.stderr:write("JSON parse error in devices: ", err, "\nResponse was: ", resp, "\n")
			return
		end

		local names = {}
		if parsed.touch then
			for _, dev in ipairs(parsed.touch) do
				if dev.name then
					table.insert(names, dev.name)
				end
			end
		end

		for _, name in ipairs(names) do
			send_hypr_command("j/monitors", function(ok2, resp_mon)
				if not ok2 then
					io.stderr:write("Error querying monitors: ", resp_mon, "\n")
					return
				end

				local mon_tbl, mpos, merr = dkjson.decode(resp_mon, 1, nil)
				if merr then
					io.stderr:write("JSON parse error in monitors: ", merr, "\nResponse:", resp_mon, "\n")
					return
				end

				local transform = nil
				for _, mon in ipairs(mon_tbl) do
					if mon.transform ~= nil then
						transform = mon.transform
						break
					end
				end

				if transform then
					local cmdstr = string.format("r/keyword device[%s]:transform %d", name, transform)
					send_hypr_command(cmdstr, function(ok3, resp3)
						if not ok3 then
							io.stderr:write("Error setting transform for ", name, ": ", resp3, "\n")
						else
							print("Set transform for device", name, "=>", transform)
						end
					end)
				end
			end)
		end
	end)
end

-- Listen to event socket
local evt_pipe = uv.new_pipe(false)
local read_buffer = ""

uv.pipe_connect(evt_pipe, evt_sockpath, function(err)
	if err then
		error("Failed to connect to event socket: " .. tostring(err))
	end

	uv.read_start(evt_pipe, function(err2, chunk)
		if err2 then
			error("Read error on event socket: " .. tostring(err2))
		end

		if not chunk then
			evt_pipe:read_stop()
			evt_pipe:close()
			return
		end

		read_buffer = read_buffer .. chunk
		while true do
			local s, e = read_buffer:find("\n", 1, true)
			if not s or not e then
				break
			end
			local line = read_buffer:sub(1, s - 1)
			read_buffer = read_buffer:sub(e + 1)

			local event, data = line:match("^([^>]+)>>([^>]*)$")
			if data == "" then
				data = nil
			end
			dispatcher:emit(event, data)
		end
	end)
end)

-- Autocmds
hypr_autocmd({ "monitoradded", "monitorremoved" }, function(data)
	print("Autocmd: monitoradded/removed ->", data)
end)

hypr_autocmd("*", function(ev, data)
	print(("Event '%s' fired with data '%s'"):format(ev, tostring(data)))
end)

hypr_autocmd("configreloaded", function()
	print("Config reloaded, syncing devices via IPC")
	sync_device_input()
end)

-- Initial sync via IPC
sync_device_input()

-- Run the libuv loop
uv.run()
