-- Test configuration for xmap.nvim
-- Usage: nvim -u test_config.lua test.swift
--        nvim -u test_config.lua test.ts
--        nvim -u test_config.lua test.tsx

-- Add current directory to runtime path
vim.opt.rtp:prepend(".")

-- Load xmap
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

-- Print success message
print("✓ xmap.nvim loaded successfully!")
print("Commands: :XmapToggle, :XmapOpen, :XmapClose")
print("Keymaps: <leader>mm (toggle), <leader>mf (focus)")
