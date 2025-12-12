-- Reload helper for xmap.nvim development
-- Usage: :luafile reload.lua

print("Reloading xmap.nvim...")

-- Close existing minimap
local ok = pcall(function()
  require("xmap").close()
end)

if ok then
  print("  ✓ Closed existing minimap")
end

-- Unload all xmap modules
local count = 0
for k, _ in pairs(package.loaded) do
  if k:match("^xmap") then
    package.loaded[k] = nil
    count = count + 1
  end
end
print("  ✓ Unloaded " .. count .. " modules")

-- Reload xmap
local success, err = pcall(function()
  local default_languages = require("xmap.config").get_default_languages()
  local default_ts_languages = require("xmap.config").get_default_languages()
  require("xmap").setup({
    width = 40, -- Wider to fit relative numbers + icons + text
    side = "right",
    filetypes = default_languages,
    treesitter = {
      enable = true,
      highlight_scopes = true,
      languages = default_ts_languages,
    },
  })
end)

if success then
  print("  ✓ xmap.nvim reloaded successfully!")
  print("\nCommands: :XmapToggle | :XmapOpen | :XmapClose | :XmapDiagnose")
  print("Run :XmapDiagnose to check Tree-sitter setup")
else
  print("  ✗ Error loading xmap: " .. tostring(err))
end
