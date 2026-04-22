
-- PURPOSE:
-- - Hot-reload xmap during interactive development.
-- CONSTRAINTS:
-- - Reset loaded modules before calling `setup()` again.

print("Reloading xmap.nvim...")
local ok = pcall(function()
  require("xmap").close()
end)

if ok then
  print("  ✓ Closed existing minimap")
end
local count = 0
for k, _ in pairs(package.loaded) do
  if k:match("^xmap") then
    package.loaded[k] = nil
    count = count + 1
  end
end
print("  ✓ Unloaded " .. count .. " modules")
local success, err = pcall(function()
  require("xmap").setup({
    width = 40,
    side = "right",
    treesitter = {
      enable = true,
      highlight_scopes = true,
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
