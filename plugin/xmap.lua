-- plugin/xmap.lua
-- Plugin loader for xmap.nvim

-- Prevent loading twice
if vim.g.loaded_xmap then
  return
end
vim.g.loaded_xmap = true

-- Define user commands
vim.api.nvim_create_user_command("XmapToggle", function()
  require("xmap").toggle()
end, { desc = "Toggle Xmap minimap" })

vim.api.nvim_create_user_command("XmapOpen", function()
  require("xmap").open()
end, { desc = "Open Xmap minimap" })

vim.api.nvim_create_user_command("XmapClose", function()
  require("xmap").close()
end, { desc = "Close Xmap minimap" })

vim.api.nvim_create_user_command("XmapRefresh", function()
  require("xmap").refresh()
end, { desc = "Refresh Xmap minimap" })

vim.api.nvim_create_user_command("XmapFocus", function()
  require("xmap").focus()
end, { desc = "Focus Xmap minimap" })
