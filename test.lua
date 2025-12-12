-- Test Lua file for xmap.nvim
-- This file contains various code structures to test Tree-sitter integration

local M = {}

-- A simple variable
local test_variable = "Hello, World!"

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

-- Final return
return M
