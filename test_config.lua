-- AI HINTS: Test configuration for xmap.nvim
-- AI HINTS: Usage: nvim -u test_config.lua test.swift
-- AI HINTS: nvim -u test_config.lua test.ts
-- AI HINTS: nvim -u test_config.lua test.tsx
-- AI HINTS: nvim -u test_config.lua test.c
-- AI HINTS: nvim -u test_config.lua test.cpp
-- AI HINTS: Header alias coverage can be exercised by setting filetype manually:
-- AI HINTS: :set ft=h
-- AI HINTS: :set ft=hpp

-- AI HINTS: Add current directory to runtime path
vim.opt.rtp:prepend(".")

-- AI HINTS: Load xmap
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

-- AI HINTS: Print success message
print("✓ xmap.nvim loaded successfully!")
print("Commands: :XmapToggle, :XmapOpen, :XmapClose")
print("Keymaps: <leader>mm (toggle), <leader>mf (focus)")
