-- lua/xmap/highlight.lua
-- Highlight group management for xmap.nvim

local M = {}

-- Define all highlight groups used by xmap
M.groups = {
  -- Minimap window background
  XmapBackground = { link = "Normal" },

  -- Normal text in minimap (slightly dimmed)
  XmapText = { fg = "#9399b2" },

  -- Line numbers in minimap (if enabled)
  XmapLineNr = { link = "LineNr" },

  -- Current viewport region (visible area in main buffer)
  XmapViewport = { bg = "#313244" },

  -- Cursor/selection in minimap
  XmapCursor = { link = "CursorLine" },

  -- Tree-sitter scope highlights (will inherit from colorscheme or use fallback)
  XmapFunction = { link = "@function" },
  XmapClass = { link = "@type" },
  XmapMethod = { link = "@method" },
  XmapVariable = { link = "@variable" },
  XmapSwiftKeyword = { link = "@keyword" },
  XmapComment = { link = "Comment" },
  XmapString = { link = "String" },
  XmapNumber = { link = "Number" },

  -- Structural indicators
  XmapScope = { link = "Title" },
  XmapBorder = { link = "FloatBorder" },

  -- Relative line numbers and arrows (explicit fg to ensure contrast in all themes)
  XmapRelativeUp = { fg = "#9ece6a", bold = true },
  XmapRelativeDown = { fg = "#f7768e", bold = true },
  XmapRelativeCurrent = { fg = "#e0af68", bold = true },
  XmapRelativeNumber = { link = "LineNr" }, -- Dimmed numbers from colorscheme
  XmapRelativeKeyword = { fg = "#bb9af7", bold = true },
  XmapRelativeEntity = { fg = "#7dcfff" },

  -- Comment markers
  XmapCommentNormal = { link = "Comment" }, -- Regular comments
  XmapCommentDoc = { link = "SpecialComment" }, -- Doc comments (///)
  XmapCommentBold = { bold = true }, -- Bold text for marker descriptions
  XmapCommentMark = { link = "SpecialComment", bold = true }, -- MARK: marker
  XmapCommentTodo = { link = "Todo", bold = true }, -- TODO: marker
  XmapCommentFixme = { link = "Error", bold = true }, -- FIXME: marker
  XmapCommentNote = { link = "SpecialComment", bold = true }, -- NOTE: marker
  XmapCommentWarning = { link = "WarningMsg", bold = true }, -- WARNING: marker
  XmapCommentBug = { link = "ErrorMsg", bold = true }, -- BUG: marker
}

-- Fallback colors (used if colorscheme doesn't provide them)
local fallback_colors = {
  XmapFunction = { fg = "#7aa2f7", bold = true }, -- Blue
  XmapClass = { fg = "#bb9af7", bold = true }, -- Purple
  XmapVariable = { fg = "#9ece6a" }, -- Green
  XmapSwiftKeyword = { fg = "#bb9af7" }, -- Purple
  -- Explicit arrow colors for reliable up/down contrast
  XmapRelativeUp = { fg = "#9ece6a", bold = true }, -- Green
  XmapRelativeDown = { fg = "#f7768e", bold = true }, -- Red
  XmapRelativeCurrent = { fg = "#e0af68", bold = true }, -- Yellow
  XmapRelativeNumber = { fg = "#565f89" }, -- Dimmed gray
  XmapRelativeKeyword = { fg = "#bb9af7", bold = true }, -- Purple (keywords)
  XmapRelativeEntity = { fg = "#7dcfff" }, -- Cyan (entity names)
}

-- Setup highlight groups
function M.setup()
  for group_name, group_def in pairs(M.groups) do
    if group_def.link then
      -- Get the actual colors from the linked group
      local link_name = group_def.link
      local link_hl = vim.api.nvim_get_hl(0, { name = link_name, link = false })

      if link_hl and link_hl.fg then
        -- Copy the actual colors instead of just linking
        local new_hl = vim.tbl_extend("force", link_hl, {})
        -- Preserve any additional attributes from group_def
        if group_def.bold then new_hl.bold = true end
        if group_def.italic then new_hl.italic = true end
        vim.api.nvim_set_hl(0, group_name, new_hl)
      elseif fallback_colors[group_name] then
        -- Use fallback color if linked group has no fg color
        vim.api.nvim_set_hl(0, group_name, fallback_colors[group_name])
      else
        -- Last resort: just link
        vim.api.nvim_set_hl(0, group_name, { link = group_def.link })
      end
    else
      vim.api.nvim_set_hl(0, group_name, group_def)
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
