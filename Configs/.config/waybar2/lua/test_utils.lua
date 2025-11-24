#!/usr/bin/env lua5.1
--[[
  Unit tests for utils.lua module
  
  Run with: lua test_utils.lua
  Dependencies: utils.lua, luv (libuv)
]]

-- Simple test framework
local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error(string.format("Assertion failed: %s\n  Expected: %s\n  Actual: %s", 
      message or "values not equal", tostring(expected), tostring(actual)))
  end
end

local function assert_true(value, message)
  if not value then
    error(string.format("Assertion failed: %s", message or "value is not true"))
  end
end

local function assert_false(value, message)
  if value then
    error(string.format("Assertion failed: %s", message or "value is not false"))
  end
end

local function assert_not_nil(value, message)
  if value == nil then
    error(string.format("Assertion failed: %s", message or "value is nil"))
  end
end

local function assert_type(value, expected_type, message)
  local actual_type = type(value)
  if actual_type ~= expected_type then
    error(string.format("Assertion failed: %s\n  Expected type: %s\n  Actual type: %s", 
      message or "type mismatch", expected_type, actual_type))
  end
end

-- Test runner
local test_count = 0
local passed_count = 0
local failed_tests = {}

local function run_test(test_name, test_fn)
  test_count = test_count + 1
  local success, error_msg = pcall(test_fn)
  if success then
    passed_count = passed_count + 1
    print(string.format("  ✓ %s", test_name))
  else
    table.insert(failed_tests, {name = test_name, error = error_msg})
    print(string.format("  ✗ %s", test_name))
  end
end

-- Import utils module
local Utils = require("utils")

print("Running Utils Module Tests\n")

-- ============================================================================
-- String Utilities Tests
-- ============================================================================

print("String Utilities:")

run_test("trim() removes leading/trailing whitespace", function()
  assert_equal(Utils.trim("  hello  "), "hello", "trim should remove spaces")
  assert_equal(Utils.trim("\t\nworld\n\t"), "world", "trim should remove tabs/newlines")
  assert_equal(Utils.trim("no_spaces"), "no_spaces", "trim should preserve content without spaces")
end)

run_test("starts_with() checks string prefix", function()
  assert_true(Utils.starts_with("hello world", "hello"), "should match prefix")
  assert_false(Utils.starts_with("hello world", "world"), "should not match non-prefix")
  assert_false(Utils.starts_with("hi", "hello"), "should handle short strings")
end)

run_test("ends_with() checks string suffix", function()
  assert_true(Utils.ends_with("hello world", "world"), "should match suffix")
  assert_false(Utils.ends_with("hello world", "hello"), "should not match non-suffix")
  assert_false(Utils.ends_with("hi", "hello"), "should handle short strings")
end)

run_test("split() separates strings by delimiter", function()
  local result = Utils.split("a,b,c", ",")
  assert_equal(#result, 3, "split should create 3 parts")
  assert_equal(result[1], "a", "first part should be 'a'")
  assert_equal(result[2], "b", "second part should be 'b'")
  assert_equal(result[3], "c", "third part should be 'c'")
end)

run_test("split() handles single delimiter", function()
  local result = Utils.split("single", ",")
  assert_equal(#result, 1, "split should return single element")
  assert_equal(result[1], "single", "should preserve original string")
end)

-- ============================================================================
-- Table Utilities Tests
-- ============================================================================

print("\nTable Utilities:")

run_test("deep_copy() creates independent copy", function()
  local original = {a = 1, b = {c = 2, d = 3}}
  local copy = Utils.deep_copy(original)
  
  assert_equal(copy.a, 1, "top level value should match")
  assert_equal(copy.b.c, 2, "nested value should match")
  
  copy.a = 99
  copy.b.c = 88
  assert_equal(original.a, 1, "original should not be modified")
  assert_equal(original.b.c, 2, "original nested value should not be modified")
end)

run_test("merge() combines tables", function()
  local t1 = {a = 1, b = 2}
  local t2 = {b = 20, c = 3}
  local result = Utils.merge(t1, t2)
  
  assert_equal(result.a, 1, "should preserve t1 unique values")
  assert_equal(result.b, 20, "should override with t2 values")
  assert_equal(result.c, 3, "should add t2 new values")
end)

-- ============================================================================
-- File Path Tests
-- ============================================================================

print("\nFile Path Utilities:")

run_test("get_xdg_dir() returns valid paths", function()
  local home = os.getenv("HOME")
  local config = Utils.get_xdg_dir("config")
  
  assert_not_nil(config, "config dir should not be nil")
  assert_true(config:match(home or os.getenv("USER")), "config path should include home directory")
end)

run_test("file_exists() detects existing files", function()
  -- Create temp file
  local tmpfile = os.tmpname()
  local f = io.open(tmpfile, "w")
  f:close()
  
  assert_true(Utils.file_exists(tmpfile), "file_exists should detect created file")
  os.remove(tmpfile)
  assert_false(Utils.file_exists(tmpfile), "file_exists should return false after removal")
end)

run_test("dir_exists() detects directories", function()
  local home = os.getenv("HOME")
  assert_true(Utils.dir_exists(home), "dir_exists should detect home directory")
  assert_false(Utils.dir_exists("/nonexistent/path/xyz"), "dir_exists should return false for missing dir")
end)

-- ============================================================================
-- JSON Operations Tests
-- ============================================================================

print("\nJSON Operations:")

run_test("json_encode() serializes tables", function()
  local data = {name = "test", value = 42}
  local json_str = Utils.json_encode(data)
  
  assert_type(json_str, "string", "json_encode should return string")
  assert_true(json_str:match("test"), "json should contain 'test'")
  assert_true(json_str:match("42"), "json should contain '42'")
end)

run_test("json_decode() parses JSON strings", function()
  local json_str = '{"name":"test","value":42}'
  local data = Utils.json_decode(json_str)
  
  assert_not_nil(data, "json_decode should return non-nil")
  if data then
    assert_equal(data.name, "test", "decoded name should match")
    assert_equal(data.value, 42, "decoded value should match")
  end
end)

run_test("json_encode/decode round-trip", function()
  local original = {
    string_val = "hello",
    number_val = 123,
    bool_val = true,
    nested = {inner = "value"}
  }
  
  local json_str = Utils.json_encode(original)
  local decoded = Utils.json_decode(json_str)
  
  assert_equal(decoded.string_val, original.string_val, "string should round-trip")
  assert_equal(decoded.number_val, original.number_val, "number should round-trip")
  assert_equal(decoded.bool_val, original.bool_val, "bool should round-trip")
  assert_equal(decoded.nested.inner, original.nested.inner, "nested value should round-trip")
end)

-- ============================================================================
-- Environment Variable Tests
-- ============================================================================

print("\nEnvironment Variables:")

run_test("get_env() retrieves environment variables", function()
  os.setenv("TEST_VAR", "test_value")
  local value = Utils.get_env("TEST_VAR")
  assert_equal(value, "test_value", "get_env should retrieve set variable")
end)

run_test("get_env() returns default for missing variables", function()
  local value = Utils.get_env("NONEXISTENT_TEST_VAR", "default_value")
  assert_equal(value, "default_value", "get_env should return default for missing variable")
end)

-- ============================================================================
-- Hashing Tests
-- ============================================================================

print("\nHashing:")

run_test("hash_file() computes consistent hash", function()
  local tmpfile = os.tmpname()
  local f = io.open(tmpfile, "w")
  f:write("test content")
  f:close()
  
  local hash1 = Utils.hash_file(tmpfile)
  local hash2 = Utils.hash_file(tmpfile)
  
  assert_equal(hash1, hash2, "hash should be consistent for same file")
  assert_not_nil(hash1, "hash should not be nil")
  
  os.remove(tmpfile)
end)

run_test("hash_file() differs for different content", function()
  local tmpfile1 = os.tmpname()
  local tmpfile2 = os.tmpname()
  
  local f1 = io.open(tmpfile1, "w")
  f1:write("content1")
  f1:close()
  
  local f2 = io.open(tmpfile2, "w")
  f2:write("content2")
  f2:close()
  
  local hash1 = Utils.hash_file(tmpfile1)
  local hash2 = Utils.hash_file(tmpfile2)
  
  assert_not_equal = function(actual, expected, message)
    if actual == expected then
      error(string.format("Assertion failed: %s\n  Both values are: %s", 
        message or "values are equal", tostring(actual)))
    end
  end
  
  assert_not_equal(hash1, hash2, "different files should have different hashes")
  
  os.remove(tmpfile1)
  os.remove(tmpfile2)
end)

-- ============================================================================
-- Summary
-- ============================================================================

print("\n" .. string.rep("=", 50))
print(string.format("Tests: %d/%d passed", passed_count, test_count))

if #failed_tests > 0 then
  print("\nFailed Tests:")
  for _, test in ipairs(failed_tests) do
    print(string.format("  - %s", test.name))
    print(string.format("    Error: %s", test.error:gsub("\n", "\n    ")))
  end
  os.exit(1)
else
  print("All tests passed!")
  os.exit(0)
end
