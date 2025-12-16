-- scripts/qa_follow_active_buffer.lua
-- Headless regression check: minimap should follow the active buffer/window.

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(string.format("%s (expected %s, got %s)", message, tostring(expected), tostring(actual)))
  end
end

local xmap = require("xmap")
local minimap = require("xmap.minimap")

vim.cmd("silent edit test.swift")
vim.bo.filetype = "swift"

xmap.open()

local first_buf = vim.api.nvim_get_current_buf()
assert_eq(minimap.state.main_bufnr, first_buf, "minimap did not attach to initial buffer")

vim.cmd("silent enew")
vim.bo.filetype = "swift"
vim.api.nvim_buf_set_name(0, "xmap://qa.swift")
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  "struct QA {",
  "  func ok() {}",
  "}",
})

local second_buf = vim.api.nvim_get_current_buf()
vim.wait(200, function()
  return minimap.state.main_bufnr == second_buf
end, 10)

assert_eq(minimap.state.main_bufnr, second_buf, "minimap did not follow active buffer")

vim.cmd("silent buffer " .. first_buf)
vim.wait(200, function()
  return minimap.state.main_bufnr == first_buf
end, 10)

assert_eq(minimap.state.main_bufnr, first_buf, "minimap did not follow back to the remaining buffer")

vim.cmd("silent bdelete! " .. second_buf)
assert_eq(minimap.state.is_open, true, "minimap closed when another supported buffer still existed")

vim.cmd("silent bdelete! " .. first_buf)
vim.wait(200, function()
  return not minimap.state.is_open
end, 10)

assert_eq(minimap.state.is_open, false, "minimap did not close when last supported buffer was deleted")

print("OK: minimap follows active buffer and closes on last buffer")
vim.cmd("qa!")
