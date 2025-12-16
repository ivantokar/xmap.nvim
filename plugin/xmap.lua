-- plugin/xmap.lua
-- Plugin loader for xmap.nvim
--
-- Neovim loads files in `plugin/` automatically on startup.
-- This file is responsible only for defining user-facing commands.
-- The actual implementation lives in `lua/xmap/`.

-- Prevent loading twice
if vim.g.loaded_xmap then
  return
end
vim.g.loaded_xmap = true

-- Define user commands
-- Commands call into the public API (`lua/xmap/init.lua`).
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

vim.api.nvim_create_user_command("XmapDiagnose", function()
  require("xmap").diagnose()
end, { desc = "Run Xmap diagnostics" })
