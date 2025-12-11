-- lua/xmap/init.lua
-- Main API for xmap.nvim

local M = {}

-- Module references
local config = require("xmap.config")
local highlight = require("xmap.highlight")
local treesitter = require("xmap.treesitter")
local minimap = require("xmap.minimap")
local navigation = require("xmap.navigation")

-- Plugin state
M._initialized = false

-- Setup function
-- @param opts table: User configuration options
function M.setup(opts)
  -- Merge user config with defaults
  config.setup(opts or {})

  -- Initialize highlight groups
  highlight.setup()

  -- Initialize Tree-sitter if available
  treesitter.setup()

  -- Set up global keymaps if configured
  M.setup_global_keymaps()

  -- Set up autocommands for auto-open
  M.setup_auto_open()

  -- Refresh highlights on colorscheme change
  vim.api.nvim_create_autocmd("ColorScheme", {
    pattern = "*",
    callback = function()
      highlight.refresh()
    end,
  })

  M._initialized = true
end

-- Set up global keymaps
function M.setup_global_keymaps()
  local opts = config.get()

  -- Toggle keymap
  if opts.keymaps.toggle then
    vim.keymap.set("n", opts.keymaps.toggle, function()
      M.toggle()
    end, { silent = true, desc = "Toggle Xmap minimap" })
  end

  -- Focus keymap
  if opts.keymaps.focus then
    vim.keymap.set("n", opts.keymaps.focus, function()
      M.focus()
    end, { silent = true, desc = "Focus Xmap minimap" })
  end
end

-- Set up auto-open functionality
function M.setup_auto_open()
  local opts = config.get()

  if not opts.auto_open then
    return
  end

  -- Auto-open minimap for supported filetypes
  vim.api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
    pattern = "*",
    callback = function()
      local filetype = vim.bo.filetype

      -- Check if filetype is supported
      if config.is_filetype_supported(filetype) then
        -- Only open if not already open
        if not minimap.is_open() then
          M.open()
        end
      end
    end,
  })
end

-- Open minimap
function M.open()
  if not M._initialized then
    M.setup()
  end

  minimap.open()
end

-- Close minimap
function M.close()
  minimap.close()
end

-- Toggle minimap
function M.toggle()
  if not M._initialized then
    M.setup()
  end

  minimap.toggle()
end

-- Refresh minimap (force redraw)
function M.refresh()
  if minimap.is_open() then
    minimap.update()
  end
end

-- Focus minimap window
function M.focus()
  if not minimap.is_open() then
    vim.notify("Minimap is not open", vim.log.levels.WARN)
    return
  end

  if minimap.state.winid then
    navigation.focus_minimap(minimap.state.winid)
  end
end

-- Check if minimap is open
-- @return boolean
function M.is_open()
  return minimap.is_open()
end

-- Get current configuration
-- @return table: Current configuration
function M.get_config()
  return config.get()
end

-- Update configuration at runtime
-- @param opts table: Configuration options to update
function M.update_config(opts)
  local current = config.get()
  config.options = vim.tbl_deep_extend("force", current, opts or {})

  -- Refresh if minimap is open
  if minimap.is_open() then
    M.refresh()
  end
end

-- Get plugin version
M.version = "0.1.0"

return M
