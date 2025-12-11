-- lua/xmap/highlight.lua
-- Highlight group management for xmap.nvim

local M = {}

-- Define all highlight groups used by xmap
M.groups = {
  -- Minimap window background
  XmapBackground = { link = "Normal" },

  -- Normal text in minimap
  XmapText = { link = "Comment" },

  -- Line numbers in minimap (if enabled)
  XmapLineNr = { link = "LineNr" },

  -- Current viewport region (visible area in main buffer)
  XmapViewport = { link = "Visual" },

  -- Cursor/selection in minimap
  XmapCursor = { link = "CursorLine" },

  -- Swift structural highlights (matching editor)
  XmapFunction = { link = "@function" },
  XmapClass = { link = "@type" },
  XmapStruct = { link = "@type" },
  XmapEnum = { link = "@type" },
  XmapProtocol = { link = "@interface" },
  XmapExtension = { link = "@type" },
  XmapProperty = { link = "@property" },
  XmapInit = { link = "@constructor" },
  XmapMethod = { link = "@method" },

  -- MARK comments (section headers)
  XmapMark = { link = "Title" },

  -- Fallback highlights
  XmapVariable = { link = "@variable" },
  XmapComment = { link = "@comment" },
  XmapKeyword = { link = "@keyword" },

  -- Structural indicators
  XmapScope = { link = "Title" },
  XmapBorder = { link = "FloatBorder" },

  -- Relative jump indicator
  XmapRelativeUp = { link = "DiffDelete" },
  XmapRelativeDown = { link = "DiffAdd" },
  XmapRelativeCurrent = { link = "DiffText" },
}

-- Setup highlight groups
function M.setup()
  for group_name, group_def in pairs(M.groups) do
    -- Check if highlight group already exists
    local exists = vim.fn.hlexists(group_name) == 1

    if not exists then
      -- Create the highlight group
      if group_def.link then
        vim.api.nvim_set_hl(0, group_name, { link = group_def.link, default = true })
      else
        vim.api.nvim_set_hl(0, group_name, vim.tbl_extend("force", group_def, { default = true }))
      end
    end
  end
end

-- Apply highlight to a buffer region
-- @param bufnr number: Buffer number
-- @param ns_id number: Namespace ID
-- @param hl_group string: Highlight group name
-- @param line number: Line number (0-indexed)
-- @param col_start number: Start column (0-indexed)
-- @param col_end number: End column (-1 for end of line)
function M.apply(bufnr, ns_id, hl_group, line, col_start, col_end)
  pcall(vim.api.nvim_buf_add_highlight, bufnr, ns_id, hl_group, line, col_start, col_end)
end

-- Clear highlights in buffer
function M.clear(bufnr, ns_id, line_start, line_end)
  line_start = line_start or 0
  line_end = line_end or -1
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, ns_id, line_start, line_end)
end

-- Create a namespace for xmap highlights
function M.create_namespace(name)
  return vim.api.nvim_create_namespace("xmap_" .. name)
end

-- Refresh all highlight groups (useful when colorscheme changes)
function M.refresh()
  M.setup()
end

return M
