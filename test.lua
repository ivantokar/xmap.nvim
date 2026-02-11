-- Test Lua file for xmap.nvim
-- This file contains various code structures to test Tree-sitter integration

local M = {}

-- TODO: Add error handling
-- FIXME: Improve performance
-- NOTE: This is a test file

-- A simple variable
local test_variable = "Hello, World!"
local another_var = 42

-- Global function
function setup_global()
  print("Global setup")
end

-- A function definition
function M.setup(opts)
  local config = opts or {}

  -- Nested function
  local function validate_config(cfg)
    if not cfg then
      return false
    end
    return true
  end

  if validate_config(config) then
    print("Config is valid")
  end

  return M
end

-- Another function
function M.render_line(line, line_nr)
  local trimmed = vim.trim(line)

  if #trimmed == 0 then
    return ""
  end

  return trimmed
end

-- Class-like table
M.state = {
  bufnr = nil,
  winid = nil,
  is_open = false,
}

-- Method-like function
function M.open()
  if M.state.is_open then
    return
  end

  M.state.is_open = true
  print("Opening...")
end

function M.close()
  if not M.state.is_open then
    return
  end

  M.state.is_open = false
  print("Closing...")
end

-- Toggle function
function M.toggle()
  if M.state.is_open then
    M.close()
  else
    M.open()
  end
end

-- Complex function with multiple lines
function M.process_buffer(bufnr, opts)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local processed = {}

  for i, line in ipairs(lines) do
    local rendered = M.render_line(line, i)
    table.insert(processed, rendered)
  end

  return processed
end

-- Arrow function style (module method)
M.validate = function(input)
  return input ~= nil
end

-- Another module method
M.transform = function(data)
  local result = {}
  for k, v in pairs(data) do
    result[k] = tostring(v)
  end
  return result
end

-- Local function
local function helper_function(arg)
  -- HACK: Quick workaround for testing
  return arg * 2
end

-- Function with return statement
function M.calculate(a, b)
  if a > b then
    return a - b
  end
  return b - a
end

-- WARNING: Deprecated function
function M.old_method()
  -- BUG: This doesn't work correctly
  return nil
end

--- Documentation comment
--- This is a documented function
--- @param value any
--- @return boolean
function M.is_valid(value)
  return value ~= nil and value ~= ""
end

-- Final return
return M
