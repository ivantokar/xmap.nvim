-- PURPOSE:
-- - Load xmap from the current checkout with stable local test defaults.

vim.opt.rtp:prepend(".")
require("xmap").setup({
  width = 25,
  side = "right",
  auto_open = false,

  treesitter = {
    enable = true,
    highlight_scopes = true,
  },

  navigation = {
    show_relative_line = true,
    auto_center = true,
  },
})
print("✓ xmap.nvim loaded successfully!")
print("Commands: :XmapToggle, :XmapOpen, :XmapClose")
print("Keymaps: <leader>mm (toggle), <leader>mf (focus)")
