-- scripts/qa_smoke_languages.lua
-- Headless smoke check: ensure xmap opens/closes across bundled filetypes.

local function assert_true(value, message)
  if not value then
    error(message)
  end
end

local xmap = require("xmap")
local minimap = require("xmap.minimap")

local cases = {
  { path = "test.lua", filetype = "lua" },
  { path = "test.swift", filetype = "swift" },
  { path = "test.ts", filetype = "typescript" },
  { path = "test.tsx", filetype = "typescriptreact" },
}

for _, case in ipairs(cases) do
  vim.cmd("silent edit " .. case.path)
  vim.bo.filetype = case.filetype

  xmap.open()
  vim.wait(100, function()
    return minimap.state.is_open
  end, 10)

  local current_buf = vim.api.nvim_get_current_buf()
  assert_true(minimap.state.is_open, "minimap did not open for " .. case.filetype)
  assert_true(minimap.state.main_bufnr == current_buf, "main buffer mismatch for " .. case.filetype)

  xmap.close()
  vim.wait(100, function()
    return not minimap.state.is_open
  end, 10)

  assert_true(not minimap.state.is_open, "minimap did not close for " .. case.filetype)
end

print("OK: xmap smoke checks passed for all bundled languages")
vim.cmd("qa!")
