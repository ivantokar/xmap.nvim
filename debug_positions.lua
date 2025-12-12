-- Debug minimap line highlighting positions
-- Run with: :luafile debug_positions.lua

print("=== Debugging Minimap Line Positions ===\n")

local minimap = require("xmap.minimap")
local minimap_bufnr = minimap.state.bufnr

if not minimap_bufnr or not vim.api.nvim_buf_is_valid(minimap_bufnr) then
  print("ERROR: Minimap not open")
  return
end

local lines = vim.api.nvim_buf_get_lines(minimap_bufnr, 0, 10, false)

print("First 10 minimap lines:\n")
for i, line in ipairs(lines) do
  print(string.format("Line %d: '%s'", i, line))
  print(string.format("  Length: %d", #line))

  -- Try to find keywords
  local text_after_icon = line:sub(8)
  print(string.format("  After pos 8: '%s'", text_after_icon))

  local keywords = { "func", "class", "let", "var", "struct" }
  for _, kw in ipairs(keywords) do
    local kw_start, kw_end = text_after_icon:find("^" .. kw .. " ")
    if kw_start then
      print(string.format("  Found '%s' at substring pos %d-%d", kw, kw_start, kw_end))
      local kw_pos_in_line = 7 + kw_start - 1
      local kw_end_pos_in_line = 7 + kw_end - 1
      print(string.format("  Full line 0-indexed: keyword at %d-%d", kw_pos_in_line, kw_end_pos_in_line))
      break
    end
  end
  print()
end

print("\n=== Checking highlight groups ===")
local ns = minimap.ns_syntax
local extmarks = vim.api.nvim_buf_get_extmarks(minimap_bufnr, ns, 0, -1, { details = true })
print(string.format("Found %d extmarks in syntax namespace", #extmarks))
for i = 1, math.min(20, #extmarks) do
  local mark = extmarks[i]
  print(string.format("Line %d, col %d-%d: %s", mark[2] + 1, mark[3], mark[4].end_col or -1, mark[4].hl_group or "nil"))
end
