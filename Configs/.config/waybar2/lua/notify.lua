#!/usr/bin/env lua5.1
--[[
  Notification Module for HyDE Waybar Manager
  
  Provides libnotify integration for user notifications.
  Automatically falls back to notify-send if libnotify Lua bindings are unavailable.
  
  Usage:
    local notify = require("notify")
    notify.success("Operation completed")
    notify.error("Something went wrong")
    notify.info("Information message")
    notify.warn("Warning message")
]]

local Utils = require("utils")

local Notify = {}

-- Notification urgency levels
Notify.URGENCY_LOW = "low"
Notify.URGENCY_NORMAL = "normal"
Notify.URGENCY_CRITICAL = "critical"

-- Timeout in milliseconds (0 = use default, -1 = never expires)
Notify.TIMEOUT_SHORT = 3000
Notify.TIMEOUT_NORMAL = 5000
Notify.TIMEOUT_LONG = 10000
Notify.TIMEOUT_NEVER = -1

-- ============================================================================
-- NOTIFICATION BACKEND DETECTION
-- ============================================================================

-- Check if notify-send is available
local function has_notify_send()
	local _, _, code = Utils.run_command("which", { "notify-send" })
	return code == 0
end

-- Check if libnotify Lua bindings are available
local function has_libnotify()
	local success = pcall(function()
		require("libnotify")
	end)
	return success
end

-- Detect and store available backend
local function get_backend()
	if has_libnotify() then
		return "libnotify"
	elseif has_notify_send() then
		return "notify-send"
	else
		return "none"
	end
end

local backend = get_backend()
Utils.log("notify", "using backend: " .. backend, "debug")

-- ============================================================================
-- LIBNOTIFY IMPLEMENTATION
-- ============================================================================

local function notify_with_libnotify(title, message, urgency, timeout, icon)
	local ln = require("libnotify")
	
	-- Initialize if needed
	if not ln.is_initted() then
		ln.init("HyDE Waybar")
	end
	
	-- Create notification
	local notification = ln.notification_new(title, message, icon or "dialog-information")
	
	-- Set urgency
	if urgency == Notify.URGENCY_LOW then
		notification:set_urgency(ln.URGENCY_LOW)
	elseif urgency == Notify.URGENCY_CRITICAL then
		notification:set_urgency(ln.URGENCY_CRITICAL)
	else
		notification:set_urgency(ln.URGENCY_NORMAL)
	end
	
	-- Set timeout (in milliseconds)
	if timeout and timeout ~= 0 then
		notification:set_timeout(timeout)
	end
	
	-- Show notification
	notification:show()
end

-- ============================================================================
-- NOTIFY-SEND IMPLEMENTATION
-- ============================================================================

local function notify_with_notify_send(title, message, urgency, timeout, icon)
	local args = {}
	
	-- Add urgency option
	table.insert(args, "-u")
	table.insert(args, urgency or Notify.URGENCY_NORMAL)
	
	-- Add timeout if specified and not -1
	if timeout and timeout ~= -1 then
		table.insert(args, "-t")
		table.insert(args, tostring(timeout))
	end
	
	-- Add icon if specified
	if icon then
		table.insert(args, "-i")
		table.insert(args, icon)
	end
	
	-- Add title and message
	table.insert(args, title or "Notification")
	table.insert(args, message or "")
	
	-- Send notification
	return Utils.run_command("notify-send", args)
end

-- ============================================================================
-- FALLBACK IMPLEMENTATION (silent)
-- ============================================================================

local function notify_fallback(title, message, urgency, timeout, icon)
	-- Just log to debug
	Utils.log("notify", 
		string.format("%s: %s", title or "Notification", message or ""),
		"debug")
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--- Send a notification with specified urgency and timeout
---@param title string Notification title
---@param message string Notification message
---@param urgency string Urgency level (low, normal, critical)
---@param timeout number Timeout in ms (0=default, -1=never)
---@param icon string Icon name (optional)
function Notify.notify(title, message, urgency, timeout, icon)
	urgency = urgency or Notify.URGENCY_NORMAL
	timeout = timeout or Notify.TIMEOUT_NORMAL
	
	if backend == "libnotify" then
		return notify_with_libnotify(title, message, urgency, timeout, icon)
	elseif backend == "notify-send" then
		return notify_with_notify_send(title, message, urgency, timeout, icon)
	else
		notify_fallback(title, message, urgency, timeout, icon)
		return false
	end
end

--- Send a success notification (green)
---@param message string Notification message
---@param timeout number Timeout in ms (optional, default: TIMEOUT_SHORT)
function Notify.success(message, timeout)
	timeout = timeout or Notify.TIMEOUT_SHORT
	return Notify.notify("Success", message, Notify.URGENCY_LOW, timeout, "dialog-positive")
end

--- Send an info notification (blue)
---@param message string Notification message
---@param timeout number Timeout in ms (optional, default: TIMEOUT_NORMAL)
function Notify.info(message, timeout)
	timeout = timeout or Notify.TIMEOUT_NORMAL
	return Notify.notify("Information", message, Notify.URGENCY_NORMAL, timeout, "dialog-information")
end

--- Send a warning notification (yellow)
---@param message string Notification message
---@param timeout number Timeout in ms (optional, default: TIMEOUT_LONG)
function Notify.warn(message, timeout)
	timeout = timeout or Notify.TIMEOUT_LONG
	return Notify.notify("Warning", message, Notify.URGENCY_NORMAL, timeout, "dialog-warning")
end

--- Send an error notification (red)
---@param message string Notification message
---@param timeout number Timeout in ms (optional, default: TIMEOUT_NEVER)
function Notify.error(message, timeout)
	timeout = timeout or Notify.TIMEOUT_NEVER
	return Notify.notify("Error", message, Notify.URGENCY_CRITICAL, timeout, "dialog-error")
end

--- Check which backend is being used
---@return string backend name
function Notify.get_backend()
	return backend
end

--- Check if notifications are available
---@return boolean
function Notify.is_available()
	return backend ~= "none"
end

--- Set layout change notification
---@param layout_name string Name of the layout that was set
function Notify.layout_changed(layout_name)
	if not Notify.is_available() then
		return false
	end
	
	return Notify.success(
		string.format("Layout changed to: %s", layout_name),
		Notify.TIMEOUT_SHORT
	)
end

--- Set appearance change notification
---@param property string Property that was changed
---@param value string New value
function Notify.appearance_changed(property, value)
	if not Notify.is_available() then
		return false
	end
	
	return Notify.success(
		string.format("Updated %s to: %s", property, value),
		Notify.TIMEOUT_SHORT
	)
end

--- Set waybar status notification
---@param status string Status message
---@param is_running boolean Whether waybar is running
function Notify.waybar_status(status, is_running)
	if not Notify.is_available() then
		return false
	end
	
	if is_running then
		return Notify.success(status, Notify.TIMEOUT_SHORT)
	else
		return Notify.warn(status, Notify.TIMEOUT_SHORT)
	end
end

--- Set configuration error notification
---@param error_msg string Error message
function Notify.config_error(error_msg)
	if not Notify.is_available() then
		return false
	end
	
	return Notify.error(
		string.format("Configuration error: %s", error_msg),
		Notify.TIMEOUT_NEVER
	)
end

return Notify
