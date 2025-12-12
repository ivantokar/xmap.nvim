-- Debug script to check actual highlight values
-- Run with: :luafile debug_highlights.lua

print("=== Current Xmap Highlight Groups ===\n")

local groups = {
  "XmapRelativeNumber",
  "XmapRelativeKeyword",
  "XmapRelativeEntity",
  "XmapRelativeUp",
  "XmapRelativeDown",
}

for _, group in ipairs(groups) do
  local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
  print(string.format("%s:", group))
  print("  fg: " .. (hl.fg and string.format("#%06x", hl.fg) or "nil"))
  print("  bg: " .. (hl.bg and string.format("#%06x", hl.bg) or "nil"))
  print("  bold: " .. tostring(hl.bold or false))
  print()
end

print("\n=== Checking if split_entity is working ===")
local nav = require("xmap.navigation")
-- Test the entity format
local test_entity = "func sendRequest"
print("Input: '" .. test_entity .. "'")
local keyword, name = test_entity:match("^(%S+)%s+(.+)$")
print("Keyword: " .. (keyword or "nil"))
print("Name: " .. (name or "nil"))
