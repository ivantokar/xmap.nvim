-- lua/xmap/init.lua
-- Main API for xmap.nvim
--
-- This module is the public entry point used by users:
--   require("xmap").setup({ ... })
--   :XmapToggle / :XmapOpen / :XmapClose / :XmapRefresh / :XmapFocus
--
-- It wires together the internal modules (config/highlight/treesitter/minimap/navigation)
-- and exposes a small stable API surface.

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
  -- Idempotent: safe to call multiple times, but users typically call once from init.lua.
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
  -- (re-apply links/fallbacks and user overrides).
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
  -- Lazy-initialize if user calls API before `setup()`.
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
  -- Lazy-initialize if user calls API before `setup()`.
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
  -- Lazy-initialize if user calls API before `setup()`.
  if not M._initialized then
    M.setup()
  end

  -- Focus should be a convenience: open the minimap if needed, then focus it.
  if not (minimap.is_open() and minimap.state.winid and vim.api.nvim_win_is_valid(minimap.state.winid)) then
    M.open()
  end

  -- Opening can fail (e.g. unsupported filetype), so check again.
  if not (minimap.is_open() and minimap.state.winid and vim.api.nvim_win_is_valid(minimap.state.winid)) then
    return
  end

  navigation.focus_minimap(minimap.state.winid)
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

-- Diagnostic function to test Tree-sitter detection
function M.diagnose()
  local bufnr = vim.api.nvim_get_current_buf()
  local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")
  local ts_lang = filetype
  if vim.treesitter and vim.treesitter.language and vim.treesitter.language.get_lang then
    ts_lang = vim.treesitter.language.get_lang(filetype) or filetype
  end
  
  print("=== xmap.nvim Diagnostics ===")
  print("Filetype: " .. filetype)
  print("Tree-sitter language: " .. ts_lang)
  
  -- Check if nvim-treesitter is available
  local ts_ok, _ = pcall(require, "nvim-treesitter")
  print("nvim-treesitter available: " .. tostring(ts_ok))
  
  -- Check if parser is available
  local parser = vim.treesitter.get_parser(bufnr, nil, { error = false })
  print("Tree-sitter parser for " .. filetype .. ": " .. tostring(parser ~= nil))
  
  if not parser then
    print("ERROR: No parser found for " .. filetype)
    print("Install with: :TSInstall " .. ts_lang)
    return
  end
  
  -- Try to parse
  local ok, trees = pcall(function() return parser:parse() end)
  print("Parse successful: " .. tostring(ok))
  
  if not ok or not trees or #trees == 0 then
    print("ERROR: Failed to parse buffer")
    return
  end
  
  -- Check structural nodes
  local treesitter = require("xmap.treesitter")
  local nodes = treesitter.get_structural_nodes(bufnr, filetype)
  print("Structural nodes found: " .. #nodes)

  if #nodes > 0 then
    print("\nStructural nodes detected by query:")
    for i = 1, math.min(10, #nodes) do
      local node = nodes[i]
      print(string.format("  Line %d: %s -> @%s", node.start_line + 1, node.node:type(), node.type))
    end
  else
    print("\nNo structural nodes found!")
    print("This might mean:")
    print("  1. The Tree-sitter query doesn't match any nodes")
    print("  2. The parser node names are different")
    print("  3. The buffer is empty or has no structural elements")

    -- Recursively search for all declaration nodes
    print("\nSearching entire tree for function/property declarations:")
    local function find_declarations(node, depth)
      if depth > 10 then return end -- Prevent infinite recursion

      local node_type = node:type()
      -- Look for anything that might be a function or property
      if node_type:match("function") or node_type:match("property") or
         node_type:match("method") or node_type:match("init") or
         node_type:match("variable") or node_type:match("constant") then
        local start_row = node:start()
        print(string.format("  Line %d: %s", start_row + 1, node_type))
      end

      -- Recursively check children
      for i = 0, node:child_count() - 1 do
        local child = node:child(i)
        if child then
          find_declarations(child, depth + 1)
        end
      end
    end

    find_declarations(trees[1]:root(), 0)

    -- Try to inspect the tree
    print("\nTree root type: " .. trees[1]:root():type())
    
    -- Try to get first few children
    local root = trees[1]:root()
    print("Root has " .. root:child_count() .. " children")
    if root:child_count() > 0 then
      print("\nAll child node types (showing up to 20):")
      for i = 0, math.min(19, root:child_count() - 1) do
        local child = root:child(i)
        if child then
          local start_row = child:start()
          print(string.format("  Line %d: %s (has %d children)", start_row + 1, child:type(), child:child_count()))

          -- If this is a class/struct, show its children
          if child:type():match("declaration") and child:child_count() > 0 then
            print("    Children of " .. child:type() .. ":")
            for j = 0, math.min(9, child:child_count() - 1) do
              local grandchild = child:child(j)
              if grandchild then
                local gc_row = grandchild:start()
                print(string.format("      Line %d: %s", gc_row + 1, grandchild:type()))
              end
            end
          end
        end
      end
    end
  end
  
  print("=== End Diagnostics ===")
end

-- Get plugin version
M.version = "0.6.0"

return M
