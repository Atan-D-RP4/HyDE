#!/usr/bin/env luajit
-- zoom.lua (libuv-based)
-- Pinch-to-zoom for Hyprland using libuv

package.cpath = package.cpath .. ";/usr/lib/lua/5.1/?.so;/usr/lib/lua/?.so;/usr/lib/libluv.so"
local uv = require("luv")

local LOCK_FILE = "/tmp/hyprland_zoom.lock"

-- Configuration
local config = {
	zoom_sensitivity = 1.5,
	zoom_acceleration = 0.8,
	zoom_min = 1.0,
	zoom_max = 4.0,
	gesture_threshold = 0.01,
	smoothing_factor = 1.3,
	deadzone = 0.05,
	continuous_zoom = true,
	zoom_momentum = 0,
	scale_damping = 0.92,
	restart_delay = 2.0,
	max_restarts = 5,
	heartbeat_interval = 30,
	debug = false,
}

local state = {
	current_zoom = 1.0,
	target_zoom = 1.0,
	gesture_active = false,
	gesture_start_zoom = 1.0,
	base_scale = 1.0,
	last_scale = 1.0,
	scale_velocity = 0.0,
	should_exit = false,
	restart_count = 0,
	libinput_process = nil,
	libinput_stdout = nil,
	restart_timer = nil,
	heartbeat_timer = nil,
	cmd_sockpath = nil,
}

local function debug_print(fmt, ...)
	if config.debug then
		local ts = os.date("%H:%M:%S")
		print(string.format("[%s DEBUG] %s", ts, string.format(fmt, ...)))
	end
end

local function log_print(fmt, ...)
	print(string.format("[%s] %s", os.date("%H:%M:%S"), string.format(fmt, ...)))
end

local function clamp(val, mn, mx)
	return math.max(mn, math.min(mx, val))
end

local function smooth_step(current, target, factor)
	return current + (target - current) * factor
end

-- Setup Hyprland socket path
local runtime = os.getenv("XDG_RUNTIME_DIR")
local sig = os.getenv("HYPRLAND_INSTANCE_SIGNATURE")
if not runtime or not sig then
	io.stderr:write("XDG_RUNTIME_DIR or HYPRLAND_INSTANCE_SIGNATURE not set; aborting\n")
	os.exit(1)
end
state.cmd_sockpath = runtime .. "/hypr/" .. sig .. "/.socket.sock"

-- send_hypr_command: connect to .socket.sock, write command (no newline), read response, callback(ok, resp)
local function send_hypr_command(cmd, cb)
	-- `cmd` should be exactly what the IPC expects (e.g., "keyword cursor:zoom_factor 1.2" or "j/devices")
	local pipe = uv.new_pipe(false)
	assert(pipe, "Failed to create pipe")

	uv.pipe_connect(pipe, state.cmd_sockpath, function(err)
		if err then
			if cb then
				cb(false, "connect error: " .. tostring(err))
			end
			return
		end

		-- write without newline
		pipe:write(cmd, function(werr)
			if werr then
				pcall(function()
					pipe:close()
				end)
				if cb then
					cb(false, "write error: " .. tostring(werr))
				end
				return
			end

			local resp = ""
			uv.read_start(pipe, function(rerr, chunk)
				if rerr then
					pcall(function()
						pipe:close()
					end)
					if cb then
						cb(false, "read error: " .. tostring(rerr))
					end
					return
				end

				if chunk then
					resp = resp .. chunk
				else -- EOF -> done
					uv.read_stop(pipe)
					pipe:close()
					if cb then
						cb(true, resp)
					end
				end
			end)
		end)
	end)
end

-- Set zoom logic now uses send_hypr_command via execute_hyprctl_async
local function set_zoom(zoom_level, immediate)
	zoom_level = clamp(zoom_level, config.zoom_min, config.zoom_max)

	if immediate then
		state.target_zoom = zoom_level
		state.current_zoom = zoom_level
	else
		state.current_zoom = smooth_step(state.current_zoom, state.target_zoom, config.smoothing_factor)
	end

	if
		state.last_applied_zoom
		and math.abs(state.current_zoom - state.last_applied_zoom) < config.gesture_threshold
	then
		debug_print("No significant zoom change (%.2f -> %.2f)", state.last_applied_zoom, state.current_zoom)
		return false
	end

	local cmd
	if state.current_zoom <= 1.01 then
		-- disable zoom (set to 1)
		cmd = "keyword cursor:zoom_factor 1"
		debug_print("Zoom disabled")
	else
		cmd = string.format("keyword cursor:zoom_factor %.2f", state.current_zoom)
		debug_print("Zoom set to %.2f (target %.2f)", state.current_zoom, state.target_zoom)
	end

	send_hypr_command(cmd, function(res)
		state.last_applied_zoom = state.current_zoom
		log_print("Response from Hyprland: %s", tostring(res))
		log_print("Set zoom to %.2f", state.current_zoom)
	end)

	return true
end

local function reset_zoom()
	debug_print("Resetting zoom to 1.0")
	set_zoom(1.0, true)
end

-- Gesture parsing (kept mostly as you had)
local function parse_gesture_event(line)
	if not line then
		return nil
	end
	state.last_heartbeat = uv.now()

	if line:match("GESTURE_PINCH_BEGIN") then
		state.gesture_active = true
		state.gesture_start_zoom = state.current_zoom
		state.base_scale = nil
		state.scale_velocity = 0.0
		debug_print("Pinch begin, zoom %.2f", state.current_zoom)
		return "begin"
	elseif line:match("GESTURE_PINCH_END") then
		state.gesture_active = false
		debug_print("Pinch end, final zoom %.2f", state.current_zoom)
		if config.zoom_momentum > 0 and math.abs(state.scale_velocity) > 0.01 then
			local momentum_zoom = state.current_zoom * (1 + state.scale_velocity * config.zoom_momentum)
			debug_print("Applying momentum: %.3f -> %.2f", state.current_zoom, momentum_zoom)
			set_zoom(momentum_zoom)
		end
		return "end"
	elseif line:match("GESTURE_PINCH_UPDATE") then
		local scale = tonumber(line:match("([%-%.%d]+)%s+@"))
		if scale and state.gesture_active then
			return "update", scale
		end
	end
	return nil
end

local function process_gesture_update(scale)
	if not state.gesture_active then
		return
	end
	if not state.base_scale then
		state.base_scale = scale
		state.last_scale = scale
		debug_print("Base scale set to %.3f", scale)
		return
	end

	local scale_delta = scale - state.last_scale
	local scale_change = scale_delta * config.scale_damping
	if math.abs(scale_change) < config.deadzone then
		return
	end

	state.scale_velocity = state.scale_velocity * 0.8 + scale_change * 0.2
	local relative_scale = scale / state.base_scale

	local zoom_factor
	if relative_scale > 1.0 then
		zoom_factor = 1.0 + (relative_scale - 1.0) * config.zoom_sensitivity
	else
		zoom_factor = 1.0 - (1.0 - relative_scale) * config.zoom_sensitivity
	end

	local acceleration = 1.0 + math.abs(relative_scale - 1.0) * config.zoom_acceleration
	zoom_factor = 1.0 + (zoom_factor - 1.0) * acceleration

	local new_zoom = state.gesture_start_zoom * zoom_factor

	debug_print(
		"Scale %.3f->%.3f delta %.3f rel %.3f factor %.3f newzoom %.2f",
		state.last_scale,
		scale,
		scale_delta,
		relative_scale,
		zoom_factor,
		new_zoom
	)

	if config.continuous_zoom then
		set_zoom(new_zoom, false)
	else
		set_zoom(new_zoom, true)
	end

	state.last_scale = scale
end

-- Cleanup: close handles, remove lock file, reset zoom
local function cleanup()
	log_print("Cleaning up...")

	-- Stop heartbeat timer
	if state.heartbeat_timer then
		pcall(function()
			state.heartbeat_timer:stop()
			state.heartbeat_timer:close()
		end)
		state.heartbeat_timer = nil
	end

	-- Stop restart timer
	if state.restart_timer then
		pcall(function()
			state.restart_timer:stop()
			state.restart_timer:close()
		end)
		state.restart_timer = nil
	end

	-- Stop libinput process
	if state.libinput_stdout then
		pcall(function()
			uv.read_stop(state.libinput_stdout)
		end)
		pcall(function()
			state.libinput_stdout:close()
		end)
		state.libinput_stdout = nil
	end

	-- Kill libinput process
	if state.libinput_process then
		pcall(function()
			state.libinput_process:kill("sigterm")
		end)
		pcall(function()
			state.libinput_process:close()
		end)
		state.libinput_process = nil
	end

	-- Remove lock file
	uv.fs_unlink(LOCK_FILE, function(err)
		if not err then
			debug_print("Removed lockfile %s", LOCK_FILE)
		end
	end)

	reset_zoom()
	log_print("Cleanup complete")
end

-- Signal handlers (libuv)
local function setup_signals()
	local function handler(signame)
		log_print("Received signal %s, exiting...", tostring(signame))
		state.should_exit = true

		-- run cleanup and stop the loop
		cleanup()

		-- stop loop after cleanup
		uv.stop()
	end

	-- SIGINT, SIGTERM, SIGHUP
	uv.signal_start(uv.new_signal(), "sigint", function()
		handler("SIGINT")
	end)

	uv.signal_start(uv.new_signal(), "sigterm", function()
		handler("SIGTERM")
	end)

	uv.signal_start(uv.new_signal(), "sighup", function()
		handler("SIGHUP")
	end)
end

local function get_pid()
	return tostring(uv.os_getpid())
end

local function ensure_single_instance()
	-- Try to read existing lock file synchronously using os.execute
	local old_pid = nil
	local read_result = os.execute(string.format("test -f %s", LOCK_FILE))

	if read_result == 0 then
		-- Lock file exists, try to read it
		local f = io.open(LOCK_FILE, "r")
		if f then
			local content = f:read("*a")
			f:close()
			old_pid = content:match("^%s*(%d+)")

			if old_pid then
				log_print("Another instance (PID %s) is running. Killing it...", old_pid)
				os.execute(string.format("kill -9 %d 2>/dev/null", tonumber(old_pid)))
				log_print("Killed existing instance PID %s", old_pid)
			end
		end

		-- Remove old lock file
		os.remove(LOCK_FILE)
	end

	-- Write new lock file with current PID
	local f = io.open(LOCK_FILE, "w")
	if not f then
		log_print("ERROR: cannot create lock file %s", LOCK_FILE)
		return false
	end

	local pid = get_pid()
	f:write(tostring(pid) .. "\n")
	f:close()

	log_print("Lock file created: %s (PID %s)", LOCK_FILE, pid)
	return true
end

local function start_libinput_monitor()
	-- Check if libinput exists using spawn
	local found = false
	uv.spawn("sh", {
		args = { "-c", "command -v libinput >/dev/null 2>&1" },
		stdio = { nil, nil, nil },
	}, function(code, sig)
		found = (code == 0)
		if not found then
			log_print("ERROR: libinput not found in PATH")
		end
	end)

	-- Small delay to allow the check to complete
	local timer = uv.new_timer()
	assert(timer, "Failed to create timer")
	timer:start(100, 0, function()
		timer:stop()
		timer:close()

		if not found then
			return
		end

		local function print_help()
			log_print(
				"ERROR: Failed to start libinput debug-events. This is often caused by insufficient permissions to read input devices."
			)
			log_print("Possible fixes:")
			log_print("  1) Add a udev rule to allow users in the 'input' group to read devices:")
			log_print("     /etc/udev/rules.d/99-input.rules:")
			log_print('       KERNEL=="event*", SUBSYSTEM=="input", GROUP="input", MODE="0660"')
			log_print("     Restrict the devices further using something like events[8-9]*")
			log_print("     or by writing separate rules for each event<X> device as needed for better security.")
			log_print("     Then reload rules and trigger: sudo udevadm control --reload-rules && sudo udevadm trigger")
			log_print("  2) Add your user to the 'input' group:")
			log_print("     sudo usermod -aG input $USER")
			log_print("     (Log out and log back in for the group change to take effect.)")
			log_print("  3) Run the script with elevated privileges (not recommended).")
			log_print(
				"If you're already in the input group and still see problems, ensure no other process is blocking device access."
			)
		end

		local function handle_failure(reason)
			print_help()
			debug_print("libinput failure reason: %s", tostring(reason))

			if state.libinput_stdout then
				pcall(function()
					uv.read_stop(state.libinput_stdout)
				end)
				pcall(function()
					state.libinput_stdout:close()
				end)
				state.libinput_stdout = nil
			end

			if state.libinput_process then
				pcall(function()
					state.libinput_process:kill("sigterm")
				end)
				pcall(function()
					state.libinput_process:close()
				end)
				state.libinput_process = nil
			end

			state.restart_count = state.restart_count + 1
			if state.restart_count < config.max_restarts then
				log_print(
					"Retrying libinput in %.1f seconds (restart %d/%d)...",
					config.restart_delay,
					state.restart_count,
					config.max_restarts
				)

				if state.restart_timer then
					pcall(function()
						state.restart_timer:stop()
						state.restart_timer:close()
					end)
					state.restart_timer = nil
				end
				local t = uv.new_timer()
				assert(t, "Failed to create restart timer")
				state.restart_timer = t

				t:start(math.floor(config.restart_delay * 1000), 0, function()
					t:stop()
					t:close()
					state.restart_timer = nil
					if not state.should_exit then
						start_libinput_monitor()
					end
				end)
			else
				log_print("Maximum restart attempts reached for libinput; giving up.")
			end
		end

		log_print("Starting libinput monitor (attempt %d/%d)", state.restart_count + 1, config.max_restarts)

		local outpipe = uv.new_pipe(false)
		local errpipe = uv.new_pipe(false)
		state.libinput_stdout = outpipe

		local proc = uv.spawn("sh", {
			args = { "-c", "stdbuf -oL libinput debug-events" },
			stdio = { nil, outpipe, errpipe },
		}, function(code, signal)
			debug_print("libinput process exited: code=%s signal=%s", tostring(code), tostring(signal))
			pcall(function()
				uv.read_stop(errpipe)
			end)
			pcall(function()
				errpipe:close()
			end)
			if state.libinput_stdout then
				pcall(function()
					uv.read_stop(state.libinput_stdout)
				end)
				pcall(function()
					state.libinput_stdout:close()
				end)
				state.libinput_stdout = nil
			end
			state.libinput_process = nil

			if not state.should_exit and (code == nil or code ~= 0) then
				handle_failure(("exit code %s"):format(tostring(code)))
			end
		end)

		if not proc then
			handle_failure("spawn failed")
			return
		end

		state.libinput_process = proc

		uv.read_start(errpipe, function(err, chunk)
			if err then
				debug_print("Error reading libinput stderr: %s", tostring(err))
				return
			end
			if not chunk then
				pcall(function()
					uv.read_stop(errpipe)
				end)
				pcall(function()
					errpipe:close()
				end)
				return
			end

			local low = chunk:lower()
			if
				low:match("permission")
				or low:match("denied")
				or low:match("operation not permitted")
				or low:match("failed to open")
				or low:match("cannot open")
				or low:match("no such file")
				or low:match("expected device")
			then
				handle_failure("stderr indicates permission/access error: " .. chunk)
				return
			end

			debug_print("libinput stderr: %s", chunk)
		end)

		local read_buf = ""
		uv.read_start(outpipe, function(err, chunk)
			if err then
				debug_print("Error reading libinput stdout: %s", tostring(err))
				return
			end
			if not chunk then
				debug_print("libinput stdout closed")
				return
			end

			read_buf = read_buf .. chunk
			while true do
				local s, e = read_buf:find("\n", 1, true)
				if not s or not e then
					break
				end
				local line = read_buf:sub(1, s - 1)
				read_buf = read_buf:sub(e + 1)
				local etype, scale = parse_gesture_event(line)
				if etype == "update" and scale then
					process_gesture_update(scale)
				end
			end
		end)

		state.restart_count = 0

		if state.heartbeat_timer then
			pcall(function()
				state.heartbeat_timer:stop()
				state.heartbeat_timer:close()
			end)
			state.heartbeat_timer = nil
		end

		local hb = uv.new_timer()
		assert(hb, "Failed to create heartbeat timer")
		state.heartbeat_timer = hb

		hb:start(config.heartbeat_interval * 1000, config.heartbeat_interval * 1000, function()
			if state.should_exit then
				hb:stop()
				hb:close()
				state.heartbeat_timer = nil
				return
			end
			uv.spawn("pgrep", {
				args = { "-x", "Hyprland" },
				stdio = { nil, nil, nil },
			}, function(code, sig)
				if code ~= 0 then
					log_print("Hyprland appears to have exited; shutting down")
					state.should_exit = true
					cleanup()
					uv.stop()
				else
					debug_print("Heartbeat: Hyprland running")
				end
			end)
		end)
	end)

	return true
end

local function main()
	log_print("Hyprland pinch-to-zoom (luv) starting")
	if config.debug then
		log_print("Debug mode ON")
	end

	if not ensure_single_instance() then
		log_print("Failed to ensure single instance; exiting")
		return 1
	end

	setup_signals()
	reset_zoom()

	if not start_libinput_monitor() then
		log_print("Failed to start libinput monitor")
		return 1
	end

	uv.run() -- uv.run will block and drive callbacks

	cleanup() -- Cleanup on exit
	return 0
end

-- Entrypoint: parse args and run
do
	for _, v in ipairs(arg or {}) do
		if v == "--debug" then
			config.debug = true
		elseif v == "-h" or v == "--help" then
			print("Usage: zoom-luv.lua [--debug]")
			os.exit(0)
		end
	end

	local status, err = pcall(main)
	if not status then
		io.stderr:write("ERROR: ", tostring(err), "\n")
		cleanup()
		os.exit(1)
	end
end
