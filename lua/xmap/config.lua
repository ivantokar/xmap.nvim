-- lua/xmap/config.lua
-- Configuration management for xmap.nvim

local M = {}

-- Default configuration
M.defaults = {
  -- Window settings
  width = 20, -- Width of the minimap window
  side = "right", -- "right" or "left"
  auto_open = false, -- Automatically open minimap for supported filetypes

  -- Filetypes where minimap should be enabled
  filetypes = { "swift" },

  -- Filetypes to exclude
  exclude_filetypes = { "help", "terminal", "prompt", "qf", "neo-tree", "NvimTree" },

  -- Swift-specific settings
  swift = {
    -- Show MARK comments as section headers
    show_marks = true,

    -- MARK comment patterns to detect
    mark_patterns = {
      "^%s*//+%s*MARK:%s*-?%s*(.*)$",  -- // MARK: - Section or // MARK: Section
      "^%s*//+%s*MARK%s*-?%s*(.*)$",    -- // MARK - Section or // MARK Section
    },
  },

  -- Keymaps (set to false to disable default mappings)
  keymaps = {
    toggle = "<leader>mm", -- Toggle minimap
    focus = "<leader>mf", -- Focus minimap window
    jump = "<CR>", -- Jump to line (inside minimap)
    close = "q", -- Close minimap (inside minimap)
  },

  -- Tree-sitter integration
  treesitter = {
    enable = true, -- Enable Tree-sitter integration
    highlight_scopes = true, -- Highlight structural scopes (functions, classes, etc.)
    languages = { "swift" },
  },

  -- Rendering options
  render = {
    -- How to render each line:
    -- "compact" - use simplified blocks/characters
    -- "text" - use truncated actual text
    mode = "text",

    -- Maximum number of characters per line in minimap
    max_line_length = 20,

    -- Show line numbers in minimap
    show_line_numbers = false,

    -- Viewport indicator character
    viewport_char = "█",

    -- Update frequency (milliseconds)
    -- Throttle minimap updates to avoid performance issues
    -- Set lower for responsive relative indicators
    throttle_ms = 50,
  },

  -- Navigation settings
  navigation = {
    -- Show relative line indicator when jumping (notification)
    -- Note: Indicators are always visible in minimap, this is for jump confirmation
    show_relative_line = false,  -- Disabled by default since indicators are in minimap

    -- How to display relative line info when jumping:
    -- "notify" - use vim.notify
    -- "float" - floating window
    -- "virtual" - virtual text in minimap
    indicator_mode = "notify",

    -- Auto-center main window when jumping
    auto_center = true,
  },
}

-- Current user configuration
M.options = {}

-- Setup function to merge user config with defaults
function M.setup(user_config)
  M.options = vim.tbl_deep_extend("force", M.defaults, user_config or {})
  return M.options
end

-- Get current configuration
function M.get()
  if vim.tbl_isempty(M.options) then
    M.options = vim.deepcopy(M.defaults)
  end
  return M.options
end

-- Check if filetype is supported
function M.is_filetype_supported(filetype)
  local opts = M.get()

  -- Check if in exclude list
  if vim.tbl_contains(opts.exclude_filetypes, filetype) then
    return false
  end

  -- Check if in include list
  return vim.tbl_contains(opts.filetypes, filetype)
end

-- Check if Tree-sitter is enabled for current language
function M.is_treesitter_enabled(filetype)
  local opts = M.get()
  if not opts.treesitter.enable then
    return false
  end
  return vim.tbl_contains(opts.treesitter.languages, filetype)
end

return M
