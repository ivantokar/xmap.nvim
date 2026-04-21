-- AI HINTS: Test Lua file for xmap.nvim
-- AI HINTS: This file contains various code structures to test Tree-sitter integration

local M = {}

-- AI HINTS: TODO: Add error handling
-- AI HINTS: FIXME: Improve performance
-- AI HINTS: NOTE: This is a test file

-- AI HINTS: A simple variable
local test_variable = "Hello, World!"
local another_var = 42

-- AI HINTS: Global function
function setup_global()
  print("Global setup")
end

-- AI HINTS: A function definition
function M.setup(opts)
  local config = opts or {}

  -- AI HINTS: Nested function
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

-- AI HINTS: Another function
function M.render_line(line, line_nr)
  local trimmed = vim.trim(line)

  if #trimmed == 0 then
    return ""
  end

  return trimmed
end

-- AI HINTS: Class-like table
M.state = {
  bufnr = nil,
  winid = nil,
  is_open = false,
}

-- AI HINTS: Method-like function
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

-- AI HINTS: Toggle function
function M.toggle()
  if M.state.is_open then
    M.close()
  else
    M.open()
  end
end

-- AI HINTS: Complex function with multiple lines
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

-- AI HINTS: Arrow function style (module method)
M.validate = function(input)
  return input ~= nil
end

-- AI HINTS: Another module method
M.transform = function(data)
  local result = {}
  for k, v in pairs(data) do
    result[k] = tostring(v)
  end
  return result
end

-- AI HINTS: Local function
local function helper_function(arg)
  -- AI HINTS: HACK: Quick workaround for testing
  return arg * 2
end

-- AI HINTS: Function with return statement
function M.calculate(a, b)
  if a > b then
    return a - b
  end
  return b - a
end

-- AI HINTS: WARNING: Deprecated function
function M.old_method()
  -- AI HINTS: BUG: This doesn't work correctly
  return nil
end

-- AI HINTS: - Documentation comment
-- AI HINTS: - This is a documented function
-- AI HINTS: - @param value any
-- AI HINTS: - @return boolean
function M.is_valid(value)
  return value ~= nil and value ~= ""
end

-- AI HINTS: Final return
return M
