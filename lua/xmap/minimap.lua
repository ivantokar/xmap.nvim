-- lua/xmap/minimap.lua
-- Minimap window and rendering logic for xmap.nvim

local config = require("xmap.config")
local highlight = require("xmap.highlight")
local treesitter = require("xmap.treesitter")
local navigation = require("xmap.navigation")

local M = {}

local MAX_RELATIVE_DISTANCE = 999
local RELATIVE_PREFIX_TEMPLATE = string.format("%s%3d ", "→", 0)
local RELATIVE_PREFIX_LEN = #RELATIVE_PREFIX_TEMPLATE

local function format_relative_prefix(source_line, current_line)
  local delta = source_line - current_line
  local arrow = "→"
  if delta < 0 then
    arrow = "↑"
  elseif delta > 0 then
    arrow = "↓"
  end

  local distance = math.abs(delta)
  if distance > MAX_RELATIVE_DISTANCE then
    distance = MAX_RELATIVE_DISTANCE
  end

  return arrow, string.format("%s%3d ", arrow, distance)
end

-- Minimap state
M.state = {
  bufnr = nil, -- Minimap buffer number
  winid = nil, -- Minimap window ID
  main_bufnr = nil, -- Main buffer being mapped
  main_winid = nil, -- Main window being mapped
  is_open = false,
  last_update = 0, -- Timestamp of last update
  update_timer = nil, -- Throttle timer
  last_relative_update = 0, -- Timestamp of last cursor-only update
  relative_timer = nil, -- Throttle timer for cursor-only updates
  line_mapping = {}, -- Maps minimap line numbers to source line numbers
  navigation_anchor_line = nil, -- Base line for relative distances while minimap is focused
  follow_scheduled = false, -- Coalesce follow-current-buffer updates
}

local function get_relative_base_line(main_winid)
  local current_line = navigation.get_main_cursor_line(main_winid)
  if not (M.state.navigation_anchor_line and M.state.winid and vim.api.nvim_win_is_valid(M.state.winid)) then
    return current_line
  end
  if vim.api.nvim_get_current_win() ~= M.state.winid then
    return current_line
  end
  return M.state.navigation_anchor_line
end

-- Namespace for highlights
M.ns_viewport = highlight.create_namespace("viewport")
M.ns_cursor = highlight.create_namespace("cursor")
M.ns_syntax = highlight.create_namespace("syntax") -- arrows, numbers, comments
M.ns_structure = highlight.create_namespace("structure") -- Tree-sitter structural scopes

-- Create minimap buffer
-- @return number: Buffer number
function M.create_buffer()
  local buf_name = "xmap://minimap"

  -- Check if a buffer with this name already exists
  local existing_buf = vim.fn.bufnr(buf_name)
  if existing_buf ~= -1 and vim.api.nvim_buf_is_valid(existing_buf) then
    -- Delete the existing buffer
    pcall(vim.api.nvim_buf_delete, existing_buf, { force = true })
  end

  local buf = vim.api.nvim_create_buf(false, true) -- No file, scratch buffer

  -- Set buffer options
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "swapfile", false)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "buflisted", false)
  vim.api.nvim_buf_set_option(buf, "filetype", "xmap")
  vim.api.nvim_buf_set_name(buf, buf_name)

  -- Make buffer read-only after initial setup
  vim.api.nvim_buf_set_option(buf, "modifiable", true)

  return buf
end

-- Create minimap window
-- @param bufnr number: Buffer to display in minimap
-- @return number: Window ID
function M.create_window(bufnr)
  local opts = config.get()

  -- Create split window instead of floating for better integration
  -- Save current window
  local current_win = vim.api.nvim_get_current_win()

  -- Create vertical split
  if opts.side == "right" then
    vim.cmd("rightbelow vsplit")
  else
    vim.cmd("leftabove vsplit")
  end

  local win = vim.api.nvim_get_current_win()

  -- Set the buffer in the new window
  vim.api.nvim_win_set_buf(win, bufnr)

  -- Set window width
  vim.api.nvim_win_set_width(win, opts.width)

  -- Set window options
  vim.api.nvim_win_set_option(win, "number", false)
  vim.api.nvim_win_set_option(win, "relativenumber", false)
  vim.api.nvim_win_set_option(win, "cursorline", false)
  vim.api.nvim_win_set_option(win, "wrap", false)
  vim.api.nvim_win_set_option(win, "signcolumn", "no")
  vim.api.nvim_win_set_option(win, "foldcolumn", "0")
  vim.api.nvim_win_set_option(win, "winfixwidth", true)
  vim.api.nvim_win_set_option(win, "fillchars", "eob: ") -- Remove ~ for empty lines
  vim.api.nvim_win_set_option(
    win,
    "winhighlight",
    "Normal:XmapBackground,NormalNC:XmapBackground,EndOfBuffer:XmapBackground,SignColumn:XmapBackground,FoldColumn:XmapBackground"
  )

  -- Return to original window
  vim.api.nvim_set_current_win(current_win)

  return win
end

-- Get icon for a specific line based on Tree-sitter
-- @param main_bufnr number: Main buffer
-- @param line_nr number: Line number (1-indexed)
-- @param nodes_by_line table|nil: Optional lookup of start_line->node.type to avoid repeated parses
-- @return string|nil: Icon or nil
function M.get_line_icon(main_bufnr, line_nr, nodes_by_line)
  if not vim.api.nvim_buf_is_valid(main_bufnr) then
    return nil
  end

  if nodes_by_line then
    local node_type = nodes_by_line[line_nr]
    if node_type then
      return treesitter.get_icon_for_type(node_type)
    end
    return nil
  end

  -- Fallback path: compute from parser directly (slower)
  local filetype = vim.api.nvim_buf_get_option(main_bufnr, "filetype")
  if not config.is_treesitter_enabled(filetype) then
    return nil
  end

  local nodes = treesitter.get_structural_nodes(main_bufnr, filetype)
  for _, node in ipairs(nodes) do
    if node.start_line + 1 == line_nr then
      return treesitter.get_icon_for_type(node.type)
    end
  end

  return nil
end

-- Check if line is a file header comment (to exclude)
-- @param lines table: All buffer lines
-- @param line_nr number: Line number (1-indexed)
-- @return boolean: True if this is part of file header
local function is_file_header(lines, line_nr)
  if line_nr > 50 then
    return false
  end

  local function is_comment_line(trimmed)
    return trimmed:match("^//") or trimmed:match("^/%*") or trimmed:match("^%*") or trimmed:match("^%-%-") or trimmed:match("^#")
  end

  local header_end = 0
  local comment_count = 0

  for i = 1, math.min(50, #lines) do
    local trimmed = vim.trim(lines[i])

    if trimmed == "" then
      header_end = i
      goto continue
    end

    if not is_comment_line(trimmed) then
      break
    end

    comment_count = comment_count + 1
    header_end = i

    ::continue::
  end

  -- Treat as file header only if there's a real comment block at the top.
  return comment_count >= 3 and line_nr <= header_end
end

-- Extract comment text (remove markers, get first line only)
-- @param line string: Comment line
-- @return string|nil, string|nil, boolean: Cleaned comment text, marker type (MARK/TODO/etc), is_doc_comment
local function extract_comment(line)
  local trimmed = vim.trim(line)

  -- Check if this is a doc comment (///)
  local is_doc_comment = trimmed:match("^///") or trimmed:match("^//!") or trimmed:match("^%-%-%-") or trimmed:match("^/%*%*")

  -- Remove comment markers
  local text = trimmed:gsub("^///%s*", "")  -- /// doc comments
    :gsub("^//!%s*", "")  -- //! doc comments (Rust)
    :gsub("^//%s*", "")  -- // comments
    :gsub("^%-%-%-%s*", "")  -- --- doc comments (Lua)
    :gsub("^%-%-%s*", "")  -- -- comments (Lua)
    :gsub("^#%s*", "")  -- # comments (Python)
    :gsub("^/%*%s*", "")  -- /* comments
    :gsub("^%*%s*", "")   -- * continuation
    :gsub("%s*%*/$", "")  -- */ end

  if text == "" then
    return nil, nil, is_doc_comment
  end

  -- Detect special markers
  local marker = nil
  if text:match("^MARK:") then
    marker = "MARK"
    text = text:gsub("^MARK:%s*%-?%s*", "")
  elseif text:match("^TODO:") then
    marker = "TODO"
    text = text:gsub("^TODO:%s*", "")
  elseif text:match("^FIXME:") then
    marker = "FIXME"
    text = text:gsub("^FIXME:%s*", "")
  elseif text:match("^NOTE:") then
    marker = "NOTE"
    text = text:gsub("^NOTE:%s*", "")
  elseif text:match("^WARNING:") then
    marker = "WARNING"
    text = text:gsub("^WARNING:%s*", "")
  elseif text:match("^BUG:") then
    marker = "BUG"
    text = text:gsub("^BUG:%s*", "")
  end

  -- Limit to reasonable length, add ellipsis if needed
  if #text > 35 then
    text = text:sub(1, 32) .. "..."
  end

  return text, marker, is_doc_comment
end

local function extract_swift_entity(line_text)
  -- Remove leading whitespace and access modifiers
  local cleaned = line_text
    :gsub("^%s*", "")
    :gsub("^public%s+", "")
    :gsub("^private%s+", "")
    :gsub("^internal%s+", "")

  -- Swift function: func name( or func name<T>(
  local name = cleaned:match("^func%s+([%w_]+)")
  if name then return "func " .. name end

  -- Swift init
  if cleaned:match("^init%s*%(") or cleaned:match("^init%s*<") then
    return "func init"
  end

  -- Swift deinit
  if cleaned:match("^deinit%s*{") then
    return "func deinit"
  end

  -- Class/Struct/Enum/Protocol: class Name, struct Name, etc.
  name = cleaned:match("^class%s+([%w_]+)")
  if name then return "class " .. name end

  name = cleaned:match("^struct%s+([%w_]+)")
  if name then return "struct " .. name end

  name = cleaned:match("^enum%s+([%w_]+)")
  if name then return "enum " .. name end

  name = cleaned:match("^protocol%s+([%w_]+)")
  if name then return "protocol " .. name end

  -- Properties: let name: or var name:
  name = cleaned:match("^let%s+([%w_]+)%s*:")
  if name then return "let " .. name end

  name = cleaned:match("^var%s+([%w_]+)%s*:")
  if name then return "var " .. name end

  return nil
end

-- Render a single line for the minimap (structural overview only)
-- @param line string: Original line from main buffer
-- @param line_nr number: Line number (1-indexed)
-- @param main_bufnr number: Main buffer (for icon detection)
-- @param current_line number: Current line in main buffer (for relative numbers)
-- @param all_lines table: All buffer lines (for context)
-- @param nodes_by_line table|nil: Optional structural lookup
-- @return string|nil: Rendered line for minimap, or nil to skip this line
function M.render_line(line, line_nr, main_bufnr, current_line, all_lines, nodes_by_line)
  local filetype = vim.api.nvim_buf_get_option(main_bufnr, "filetype")
  local opts = config.get()

  local _, prefix = format_relative_prefix(line_nr, current_line)

  local trimmed = vim.trim(line)

  -- Include only marker comments (MARK/TODO/FIXME/...) in the minimap.
  if trimmed:match("^//") or trimmed:match("^/%*") or trimmed:match("^%*") or trimmed:match("^%-%-") or trimmed:match("^#") then
    local text, marker, is_doc_comment = extract_comment(line)
    if marker then
      return prefix .. "⚑ " .. marker .. ": " .. (text or "")
    end

    if text and not is_file_header(all_lines, line_nr) then
      local comment_icon = "󰆈"
      local comment_prefix = "//"
      if trimmed:match("^//!") then
        comment_prefix = "//!"
      elseif trimmed:match("^/%*%*") then
        comment_prefix = "/**"
      elseif trimmed:match("^/%*") then
        comment_prefix = "/*"
      elseif trimmed:match("^%*") then
        comment_prefix = "*"
      elseif is_doc_comment then
        comment_prefix = "///"
      end

      if trimmed:match("^%-%-") then
        comment_prefix = is_doc_comment and "---" or "--"
      elseif trimmed:match("^#") then
        comment_prefix = "#"
      end

      return prefix .. comment_icon .. " " .. comment_prefix .. " " .. text
    end

    return nil
  end

  -- Check if this is a structural element (function/class/etc)
  local icon = M.get_line_icon(main_bufnr, line_nr, nodes_by_line)
  local structural_text = nil
  local has_structural_data = nodes_by_line and next(nodes_by_line) ~= nil

  -- Heuristic fallback for when Tree-sitter is missing or returns no nodes
  if not icon then
    if filetype == "lua" then
      local name = trimmed:match("^local%s+function%s+([%w_%.:]+)") or trimmed:match("^function%s+([%w_%.:]+)")
      if name then
        icon = treesitter.get_icon_for_type("function")
        structural_text = "function " .. name
      end
    end
  end

  if icon then
    local entity = structural_text
    if not entity and filetype == "swift" then
      entity = extract_swift_entity(trimmed)
    end

    local compact = (entity or trimmed):gsub("%s+", " ")
    local max_len = opts.render.max_line_length or 40
    if #compact > max_len then
      compact = compact:sub(1, max_len - 3) .. "..."
    end

    return prefix .. icon .. " " .. compact
  end

  -- If we have structural data, hide non-structural lines to keep the minimap focused
  if has_structural_data then
    return nil
  end

  -- No structural data (parser missing) -> show a minimal text fallback for non-empty, non-comment lines
  if trimmed == "" then
    return nil
  end

  -- Skip obvious comment lines to reduce noise
  if trimmed:match("^%s*//") or trimmed:match("^%s*/%*") or trimmed:match("^%s*%*") or trimmed:match("^%s*%-%-") then
    return nil
  end

  local compact = trimmed:gsub("%s+", " ")
  local max_len = opts.render.max_line_length or 40
  if #compact > max_len then
    compact = compact:sub(1, max_len - 3) .. "..."
  end

  return prefix .. compact
end

-- Render entire buffer content for minimap
-- @param main_bufnr number: Main buffer to render
-- @param main_winid number: Main window (to get current line)
-- @param current_line_override number|nil: Optional base line override
-- @return table, table: Lines for minimap, line number mapping
function M.render_buffer(main_bufnr, main_winid, current_line_override)
  if not vim.api.nvim_buf_is_valid(main_bufnr) then
    return {}, {}, {}
  end

  -- Get current line in main buffer
  local current_line = current_line_override or navigation.get_main_cursor_line(main_winid)

  local lines = vim.api.nvim_buf_get_lines(main_bufnr, 0, -1, false)
  local rendered = {}
  local line_mapping = {}  -- Maps minimap line number to source line number
  local nodes_by_line = {}
  local structural_nodes = {}

  -- Build structural lookup once per render
  local filetype = vim.api.nvim_buf_get_option(main_bufnr, "filetype")
  if config.is_treesitter_enabled(filetype) then
    structural_nodes = treesitter.get_structural_nodes(main_bufnr, filetype)
    for _, node in ipairs(structural_nodes) do
      nodes_by_line[node.start_line + 1] = node.type
    end
  end

  for i, line in ipairs(lines) do
    local rendered_line = M.render_line(line, i, main_bufnr, current_line, lines, nodes_by_line)
    if rendered_line then
      table.insert(rendered, rendered_line)
      table.insert(line_mapping, i)  -- Store source line number
    end
  end

  return rendered, line_mapping, structural_nodes
end

-- Apply highlighting for relative numbers, arrows, icons, and comments
-- @param minimap_bufnr number: Minimap buffer
-- @param main_bufnr number: Main buffer
-- @param main_winid number: Main window
-- @param current_line_override number|nil: Optional base line override
function M.apply_relative_number_highlighting(minimap_bufnr, main_bufnr, main_winid, current_line_override)
  if not vim.api.nvim_buf_is_valid(minimap_bufnr) or not vim.api.nvim_buf_is_valid(main_bufnr) then
    return
  end

  -- Clear previous highlights
  highlight.clear(minimap_bufnr, M.ns_syntax)

  -- Get current line
  local current_line = current_line_override or navigation.get_main_cursor_line(main_winid)

  -- Get minimap lines
  local minimap_lines = vim.api.nvim_buf_get_lines(minimap_bufnr, 0, -1, false)

  -- Highlight each line
  for minimap_line_nr = 1, #minimap_lines do
    local line_text = minimap_lines[minimap_line_nr]

    -- Get actual source line number from mapping
    local source_line_nr = M.state.line_mapping[minimap_line_nr]
    if not source_line_nr then
      goto continue
    end

    local distance = source_line_nr - current_line
    local arrow, prefix = format_relative_prefix(source_line_nr, current_line)
    local arrow_end = #arrow
    local prefix_end = #prefix

    -- Highlight arrow (byte range for the UTF-8 arrow)
    if distance < 0 then
      highlight.apply(minimap_bufnr, M.ns_syntax, "XmapRelativeUp", minimap_line_nr - 1, 0, arrow_end)
    elseif distance > 0 then
      highlight.apply(minimap_bufnr, M.ns_syntax, "XmapRelativeDown", minimap_line_nr - 1, 0, arrow_end)
    else
      highlight.apply(minimap_bufnr, M.ns_syntax, "XmapRelativeCurrent", minimap_line_nr - 1, 0, arrow_end)
    end

    -- Highlight number + trailing space (byte indices)
    highlight.apply(minimap_bufnr, M.ns_syntax, "XmapRelativeNumber", minimap_line_nr - 1, arrow_end, prefix_end)

    -- Check for special comment markers (only highlight icon + marker name, leave text bold)
    if line_text:match("⚑ MARK:") then
      local icon_pos = line_text:find("⚑")
      local marker_end = line_text:find(":", icon_pos)
      if icon_pos and marker_end then
        highlight.apply(minimap_bufnr, M.ns_syntax, "XmapCommentMark", minimap_line_nr - 1, icon_pos - 1, marker_end)
        -- Make the rest of the line bold
        highlight.apply(minimap_bufnr, M.ns_syntax, "XmapCommentBold", minimap_line_nr - 1, marker_end + 1, -1)
      end
    elseif line_text:match("⚑ TODO:") then
      local icon_pos = line_text:find("⚑")
      local marker_end = line_text:find(":", icon_pos)
      if icon_pos and marker_end then
        highlight.apply(minimap_bufnr, M.ns_syntax, "XmapCommentTodo", minimap_line_nr - 1, icon_pos - 1, marker_end)
        highlight.apply(minimap_bufnr, M.ns_syntax, "XmapCommentBold", minimap_line_nr - 1, marker_end + 1, -1)
      end
    elseif line_text:match("⚑ FIXME:") then
      local icon_pos = line_text:find("⚑")
      local marker_end = line_text:find(":", icon_pos)
      if icon_pos and marker_end then
        highlight.apply(minimap_bufnr, M.ns_syntax, "XmapCommentFixme", minimap_line_nr - 1, icon_pos - 1, marker_end)
        highlight.apply(minimap_bufnr, M.ns_syntax, "XmapCommentBold", minimap_line_nr - 1, marker_end + 1, -1)
      end
    elseif line_text:match("⚑ NOTE:") then
      local icon_pos = line_text:find("⚑")
      local marker_end = line_text:find(":", icon_pos)
      if icon_pos and marker_end then
        highlight.apply(minimap_bufnr, M.ns_syntax, "XmapCommentNote", minimap_line_nr - 1, icon_pos - 1, marker_end)
        highlight.apply(minimap_bufnr, M.ns_syntax, "XmapCommentBold", minimap_line_nr - 1, marker_end + 1, -1)
      end
    elseif line_text:match("⚑ WARNING:") then
      local icon_pos = line_text:find("⚑")
      local marker_end = line_text:find(":", icon_pos)
      if icon_pos and marker_end then
        highlight.apply(minimap_bufnr, M.ns_syntax, "XmapCommentWarning", minimap_line_nr - 1, icon_pos - 1, marker_end)
        highlight.apply(minimap_bufnr, M.ns_syntax, "XmapCommentBold", minimap_line_nr - 1, marker_end + 1, -1)
      end
    elseif line_text:match("⚑ BUG:") then
      local icon_pos = line_text:find("⚑")
      local marker_end = line_text:find(":", icon_pos)
      if icon_pos and marker_end then
        highlight.apply(minimap_bufnr, M.ns_syntax, "XmapCommentBug", minimap_line_nr - 1, icon_pos - 1, marker_end)
        highlight.apply(minimap_bufnr, M.ns_syntax, "XmapCommentBold", minimap_line_nr - 1, marker_end + 1, -1)
      end
    else
      -- Rendered comment lines start with a comment icon; highlight the entire comment content.
      local comment_icon = "󰆈"
      local comment_icon_pos = line_text:find(comment_icon, 1, true)
      if comment_icon_pos then
        local hl_group = "XmapCommentNormal"
        local after_icon = line_text:sub(comment_icon_pos + #comment_icon):gsub("^%s*", "")
        if after_icon:match("^///") or after_icon:match("^//!") or after_icon:match("^/%*%*") or after_icon:match("^%-%-%-") then
          hl_group = "XmapCommentDoc"
        end
        highlight.apply(minimap_bufnr, M.ns_syntax, hl_group, minimap_line_nr - 1, comment_icon_pos - 1, -1)
        goto continue
      end

      -- Try to highlight keywords on ALL lines, not just structural nodes
      -- Text format: "↑ 22  let provider" or "↓  3  func init"
      -- Skip arrow (pos 0), then skip spaces and numbers, then find first letter
      local _, text_start = line_text:find("^[^%a]*") -- Skip everything that's not a letter
      text_start = text_start and text_start + 1 -- Position after non-letters

      if text_start and text_start <= #line_text then
        local text_after_numbers = line_text:sub(text_start)

        local keywords = { "func", "class", "struct", "enum", "protocol", "let", "var", "init", "private" }
        for _, keyword in ipairs(keywords) do
          local kw_start, kw_end = text_after_numbers:find("^" .. keyword .. "%s")
          if kw_start then
            -- Found keyword at start of text
            local kw_pos_in_line = text_start - 1 + kw_start - 1 -- Position in full line (0-indexed)
            local kw_end_pos_in_line = text_start - 1 + kw_end -- Don't subtract 1 - we want to include the space in keyword highlight

            -- Highlight keyword (including trailing space) with colorscheme color
            highlight.apply(minimap_bufnr, M.ns_syntax, "XmapRelativeKeyword", minimap_line_nr - 1, kw_pos_in_line, kw_end_pos_in_line)

            -- Highlight entity name after keyword (starting right after the space)
            local entity_start = kw_end_pos_in_line
            if entity_start < #line_text then
              highlight.apply(minimap_bufnr, M.ns_syntax, "XmapRelativeEntity", minimap_line_nr - 1, entity_start, -1)
            end
            break
          end
        end
      end
    end
    ::continue::
  end
end

-- Apply syntax highlighting based on Tree-sitter
-- @param minimap_bufnr number: Minimap buffer
-- @param main_bufnr number: Main buffer
function M.apply_syntax_highlighting(minimap_bufnr, main_bufnr, structural_nodes)
  if not vim.api.nvim_buf_is_valid(minimap_bufnr) or not vim.api.nvim_buf_is_valid(main_bufnr) then
    return
  end

  local opts = config.get()
  local filetype = vim.api.nvim_buf_get_option(main_bufnr, "filetype")

  if not opts.treesitter.highlight_scopes or not config.is_treesitter_enabled(filetype) then
    return
  end

  -- Clear previous structural highlights without touching relative/arrow highlights
  highlight.clear(minimap_bufnr, M.ns_structure)

  -- Build a reverse lookup: source line -> minimap line
  local line_lookup = {}
  for minimap_line, source_line in ipairs(M.state.line_mapping or {}) do
    line_lookup[source_line] = minimap_line
  end

  -- Get structural nodes from Tree-sitter
  local nodes = structural_nodes or treesitter.get_structural_nodes(main_bufnr, filetype)

  -- Apply highlights for each structural node (only if rendered in minimap)
  for _, node in ipairs(nodes) do
    local hl_group = treesitter.get_highlight_for_type(node.type)

    -- Minimaps render only key structural lines, so highlight the start line if present
    local source_line = node.start_line + 1 -- convert to 1-indexed
    local minimap_line = line_lookup[source_line]
    if minimap_line then
      highlight.apply(minimap_bufnr, M.ns_structure, hl_group, minimap_line - 1, RELATIVE_PREFIX_LEN, -1)
    end
  end

  -- Heuristic fallback when no nodes are returned (e.g., parser missing)
  if #nodes == 0 then
    local lines = vim.api.nvim_buf_get_lines(main_bufnr, 0, -1, false)
    for source_line, minimap_line in pairs(line_lookup) do
      local text = lines[source_line] or ""

      -- Basic Lua function detection: function foo(...) or local function foo(...)
      if filetype == "lua" then
        if text:match("^%s*local%s+function%s+[%w_%.:]+") or text:match("^%s*function%s+[%w_%.:]+") then
          highlight.apply(minimap_bufnr, M.ns_structure, "XmapFunction", minimap_line - 1, RELATIVE_PREFIX_LEN, -1)
        end
      end
    end
  end
end

function M.highlight_cursor_line(minimap_bufnr, minimap_line)
  if not vim.api.nvim_buf_is_valid(minimap_bufnr) then
    return
  end

  highlight.clear(minimap_bufnr, M.ns_cursor)

  if not minimap_line or minimap_line < 1 then
    return
  end

  -- Use an extmark with `hl_eol` so the highlight covers the full window width.
  pcall(vim.api.nvim_buf_set_extmark, minimap_bufnr, M.ns_cursor, minimap_line - 1, 0, {
    hl_group = "XmapCursor",
    hl_eol = true,
    hl_mode = "combine",
    priority = 100,
  })
end

-- Update only the relative prefix + highlighting for cursor moves.
function M.update_relative_only()
  if not M.state.is_open or not M.state.bufnr or not M.state.main_bufnr then
    return
  end

  if not vim.api.nvim_buf_is_valid(M.state.bufnr) or not vim.api.nvim_buf_is_valid(M.state.main_bufnr) then
    M.close()
    return
  end

  if not (M.state.main_winid and vim.api.nvim_win_is_valid(M.state.main_winid)) then
    return
  end

  local current_line = get_relative_base_line(M.state.main_winid)
  local existing_lines = vim.api.nvim_buf_get_lines(M.state.bufnr, 0, -1, false)

  local updated = {}
  local changed = false

  for minimap_line, line_text in ipairs(existing_lines) do
    local source_line = M.state.line_mapping[minimap_line]
    if source_line then
      local _, prefix = format_relative_prefix(source_line, current_line)
      local content = ""
      if #line_text >= RELATIVE_PREFIX_LEN then
        content = line_text:sub(RELATIVE_PREFIX_LEN + 1)
      end
      local new_text = prefix .. content
      updated[minimap_line] = new_text
      if new_text ~= line_text then
        changed = true
      end
    else
      updated[minimap_line] = line_text
    end
  end

  if changed then
    vim.api.nvim_buf_set_option(M.state.bufnr, "modifiable", true)
    vim.api.nvim_buf_set_lines(M.state.bufnr, 0, -1, false, updated)
    vim.api.nvim_buf_set_option(M.state.bufnr, "modifiable", false)
  end

  -- Clear background-style highlights (viewport/cursor) and refresh syntax highlights.
  highlight.clear(M.state.bufnr, M.ns_viewport)
  highlight.clear(M.state.bufnr, M.ns_cursor)
  M.apply_relative_number_highlighting(M.state.bufnr, M.state.main_bufnr, M.state.main_winid, current_line)

  if M.state.winid and vim.api.nvim_win_is_valid(M.state.winid) then
    local is_minimap_focused = vim.api.nvim_get_current_win() == M.state.winid
    if not is_minimap_focused then
      navigation.update_minimap_cursor(M.state.winid, current_line, M.state.line_mapping)
    end
    local minimap_line = vim.api.nvim_win_get_cursor(M.state.winid)[1]
    M.highlight_cursor_line(M.state.bufnr, minimap_line)
  end

  M.state.last_relative_update = vim.loop.now()
end

function M.throttled_relative_update()
  local opts = config.get()
  local now = vim.loop.now()

  if now - (M.state.last_relative_update or 0) < (opts.render.throttle_ms or 0) then
    if M.state.relative_timer then
      M.state.relative_timer:stop()
    end
    M.state.relative_timer = vim.defer_fn(function()
      M.update_relative_only()
    end, opts.render.throttle_ms)
    return
  end

  M.update_relative_only()
end

-- Update minimap content
function M.update()
  if not M.state.is_open or not M.state.bufnr or not M.state.main_bufnr then
    return
  end

  if not vim.api.nvim_buf_is_valid(M.state.bufnr) or not vim.api.nvim_buf_is_valid(M.state.main_bufnr) then
    M.close()
    return
  end

  -- Render buffer content with relative line numbers
  local current_line = get_relative_base_line(M.state.main_winid)
  local rendered_lines, line_mapping, structural_nodes = M.render_buffer(M.state.main_bufnr, M.state.main_winid, current_line)

  -- Store line mapping for navigation
  M.state.line_mapping = line_mapping

  -- Update minimap buffer
  vim.api.nvim_buf_set_option(M.state.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(M.state.bufnr, 0, -1, false, rendered_lines)
  vim.api.nvim_buf_set_option(M.state.bufnr, "modifiable", false)

  -- Apply syntax highlighting for arrows, numbers, icons, and structure
  highlight.clear(M.state.bufnr, M.ns_viewport)
  highlight.clear(M.state.bufnr, M.ns_cursor)
  M.apply_syntax_highlighting(M.state.bufnr, M.state.main_bufnr, structural_nodes)
  M.apply_relative_number_highlighting(M.state.bufnr, M.state.main_bufnr, M.state.main_winid, current_line)

  -- Update minimap cursor to follow main buffer
  if M.state.main_winid and vim.api.nvim_win_is_valid(M.state.main_winid) then
    local main_line = navigation.get_main_cursor_line(M.state.main_winid)
    if M.state.winid and vim.api.nvim_win_is_valid(M.state.winid) then
      local is_minimap_focused = vim.api.nvim_get_current_win() == M.state.winid
      if not is_minimap_focused then
        navigation.update_minimap_cursor(M.state.winid, main_line, M.state.line_mapping)
      end
      local minimap_line = vim.api.nvim_win_get_cursor(M.state.winid)[1]
      M.highlight_cursor_line(M.state.bufnr, minimap_line)
    end
  end

  M.state.last_update = vim.loop.now()
end

-- Throttled update function
function M.throttled_update()
  local opts = config.get()
  local now = vim.loop.now()

  -- Check if enough time has passed since last update
  if now - M.state.last_update < opts.render.throttle_ms then
    -- Schedule update for later
    if M.state.update_timer then
      M.state.update_timer:stop()
    end

    M.state.update_timer = vim.defer_fn(function()
      M.update()
    end, opts.render.throttle_ms)

    return
  end

  M.update()
end

-- Follow the currently active window/buffer when minimap is open.
-- This keeps the minimap in sync when switching buffers or windows.
function M._follow_current_target()
  if not M.state.is_open then
    return
  end
  if not (M.state.winid and vim.api.nvim_win_is_valid(M.state.winid)) then
    M.close()
    return
  end

  local function is_supported_target(bufnr)
    if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
      return false
    end
    if M.state.bufnr and bufnr == M.state.bufnr then
      return false
    end
    local buftype = vim.api.nvim_buf_get_option(bufnr, "buftype")
    if buftype ~= "" then
      return false
    end
    local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")
    return config.is_filetype_supported(filetype)
  end

  local function attach_target(main_bufnr, main_winid)
    local buffer_changed = main_bufnr ~= M.state.main_bufnr
    local win_changed = main_winid ~= M.state.main_winid

    if not buffer_changed and not win_changed then
      return
    end

    M.state.main_bufnr = main_bufnr
    M.state.main_winid = main_winid
    M.state.navigation_anchor_line = nil

    if buffer_changed then
      M.setup_autocommands()
      M.update()
    else
      M.throttled_relative_update()
    end
  end

  local current_winid = vim.api.nvim_get_current_win()
  local current_bufnr = vim.api.nvim_get_current_buf()

  local current_is_minimap = current_winid == M.state.winid or current_bufnr == M.state.bufnr

  if not current_is_minimap and is_supported_target(current_bufnr) then
    attach_target(current_bufnr, current_winid)
    return
  end

  if is_supported_target(M.state.main_bufnr) then
    local main_winid = M.state.main_winid
    if
      not (
        main_winid
        and vim.api.nvim_win_is_valid(main_winid)
        and vim.api.nvim_win_get_buf(main_winid) == M.state.main_bufnr
      )
    then
      main_winid = nil
      for _, winid in ipairs(vim.api.nvim_list_wins()) do
        if winid ~= M.state.winid and vim.api.nvim_win_get_buf(winid) == M.state.main_bufnr then
          main_winid = winid
          break
        end
      end
    end

    if main_winid then
      attach_target(M.state.main_bufnr, main_winid)
      return
    end
  end

  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if winid ~= M.state.winid then
      local bufnr = vim.api.nvim_win_get_buf(winid)
      if is_supported_target(bufnr) then
        attach_target(bufnr, winid)
        return
      end
    end
  end

  M.close()
end

function M.follow_current_target()
  if M.state.follow_scheduled then
    return
  end
  M.state.follow_scheduled = true
  vim.schedule(function()
    M.state.follow_scheduled = false
    M._follow_current_target()
  end)
end

-- Open minimap for current buffer
function M.open()
  -- Check if already open
  if M.state.is_open and M.state.winid and vim.api.nvim_win_is_valid(M.state.winid) then
    return
  end

  -- Get current buffer and window
  local main_bufnr = vim.api.nvim_get_current_buf()
  local main_winid = vim.api.nvim_get_current_win()

  -- Check if filetype is supported
  local filetype = vim.api.nvim_buf_get_option(main_bufnr, "filetype")
  if not config.is_filetype_supported(filetype) then
    vim.notify("Minimap not supported for filetype: " .. filetype, vim.log.levels.INFO)
    return
  end

  -- Create buffer and window
  local bufnr = M.create_buffer()
  local winid = M.create_window(bufnr)

  -- Store state
  M.state.bufnr = bufnr
  M.state.winid = winid
  M.state.main_bufnr = main_bufnr
  M.state.main_winid = main_winid
  M.state.is_open = true

  -- Set up keymaps for minimap
  navigation.setup_minimap_keymaps(bufnr, winid, main_bufnr, main_winid)

  -- Initial render
  M.update()

  -- Set up autocommands for updating minimap
  M.setup_autocommands()
end

-- Close minimap
function M.close()
  if not M.state.is_open then
    return
  end

  local minimap_bufnr = M.state.bufnr
  local minimap_winid = M.state.winid

  -- Clear timers
  if M.state.update_timer then
    M.state.update_timer:stop()
    M.state.update_timer = nil
  end
  if M.state.relative_timer then
    M.state.relative_timer:stop()
    M.state.relative_timer = nil
  end

  -- Clear autocommands
  pcall(vim.api.nvim_del_augroup_by_name, "XmapUpdate")

  -- Close window (or repurpose it if it's the last window in the tabpage)
  if minimap_winid and vim.api.nvim_win_is_valid(minimap_winid) then
    local tabpage = vim.api.nvim_win_get_tabpage(minimap_winid)
    local wins = vim.api.nvim_tabpage_list_wins(tabpage)

    if #wins > 1 then
      pcall(vim.api.nvim_win_close, minimap_winid, true)
    else
      local replacement_bufnr = nil

      if M.state.main_bufnr and vim.api.nvim_buf_is_valid(M.state.main_bufnr) and M.state.main_bufnr ~= minimap_bufnr then
        replacement_bufnr = M.state.main_bufnr
      end

      if not replacement_bufnr then
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
          if bufnr ~= minimap_bufnr and vim.api.nvim_buf_is_valid(bufnr) then
            local buftype = vim.api.nvim_buf_get_option(bufnr, "buftype")
            local listed = vim.api.nvim_buf_get_option(bufnr, "buflisted")
            if buftype == "" and listed then
              replacement_bufnr = bufnr
              break
            end
          end
        end
      end

      if replacement_bufnr then
        pcall(vim.api.nvim_win_set_buf, minimap_winid, replacement_bufnr)
      else
        pcall(vim.api.nvim_win_call, minimap_winid, function()
          vim.cmd("enew")
        end)
      end
    end
  end

  -- Delete buffer
  if minimap_bufnr and vim.api.nvim_buf_is_valid(minimap_bufnr) then
    pcall(vim.api.nvim_buf_delete, minimap_bufnr, { force = true })
  end

  -- Reset state
  M.state.bufnr = nil
  M.state.winid = nil
  M.state.main_bufnr = nil
  M.state.main_winid = nil
  M.state.is_open = false
end

-- Toggle minimap
function M.toggle()
  if M.state.is_open then
    M.close()
  else
    M.open()
  end
end

-- Set up autocommands for minimap updates
function M.setup_autocommands()
  local augroup = vim.api.nvim_create_augroup("XmapUpdate", { clear = true })

  -- Update on text changes
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = augroup,
    buffer = M.state.main_bufnr,
    callback = function()
      M.throttled_update()
    end,
  })

  -- Update on cursor movement
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = augroup,
    buffer = M.state.main_bufnr,
    callback = function()
      if M.state.bufnr and vim.api.nvim_buf_is_valid(M.state.bufnr) and M.state.line_mapping and #M.state.line_mapping > 0 then
        M.throttled_relative_update()
        return
      end
      M.throttled_update()
    end,
  })

  -- Keep a cursor highlight inside the minimap:
  -- - while focused: follows minimap cursor (navigation)
  -- - while not focused: follows main cursor mapping
  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
    group = augroup,
    buffer = M.state.bufnr,
    callback = function()
      if M.state.bufnr and M.state.winid and vim.api.nvim_win_is_valid(M.state.winid) then
        local opts = config.get()
        if opts.navigation.follow_cursor and M.state.main_winid and vim.api.nvim_win_is_valid(M.state.main_winid) then
          M.state.navigation_anchor_line = navigation.get_main_cursor_line(M.state.main_winid)
        else
          M.state.navigation_anchor_line = nil
        end
        local minimap_line = vim.api.nvim_win_get_cursor(M.state.winid)[1]
        M.highlight_cursor_line(M.state.bufnr, minimap_line)
      end
    end,
  })

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = augroup,
    buffer = M.state.bufnr,
    callback = function()
      if M.state.bufnr and M.state.winid and vim.api.nvim_win_is_valid(M.state.winid) then
        local minimap_line = vim.api.nvim_win_get_cursor(M.state.winid)[1]
        M.highlight_cursor_line(M.state.bufnr, minimap_line)

        local opts = config.get()
        if opts.navigation.follow_cursor and vim.api.nvim_get_current_win() == M.state.winid then
          if M.state.main_bufnr and M.state.main_winid then
            navigation.center_main_on_minimap_cursor(
              M.state.winid,
              M.state.main_bufnr,
              M.state.main_winid,
              M.state.line_mapping
            )
          end
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
    group = augroup,
    buffer = M.state.bufnr,
    callback = function()
      M.state.navigation_anchor_line = nil
      if not (M.state.bufnr and vim.api.nvim_buf_is_valid(M.state.bufnr)) then
        return
      end
      if not (M.state.winid and vim.api.nvim_win_is_valid(M.state.winid)) then
        return
      end
      if not (M.state.main_winid and vim.api.nvim_win_is_valid(M.state.main_winid)) then
        return
      end

      local main_line = navigation.get_main_cursor_line(M.state.main_winid)
      navigation.update_minimap_cursor(M.state.winid, main_line, M.state.line_mapping)
      local minimap_line = vim.api.nvim_win_get_cursor(M.state.winid)[1]
      M.highlight_cursor_line(M.state.bufnr, minimap_line)

      if M.state.main_bufnr and vim.api.nvim_buf_is_valid(M.state.main_bufnr) then
        M.update_relative_only()
      end
    end,
  })

  -- Update on buffer write
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = augroup,
    buffer = M.state.main_bufnr,
    callback = function()
      M.update()
    end,
  })

  -- Close minimap when main buffer is closed, deleted, or unloaded
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete", "BufUnload" }, {
    group = augroup,
    buffer = M.state.main_bufnr,
    callback = function()
      M.follow_current_target()
    end,
  })

  -- Keep minimap target in sync when switching buffers/windows.
  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "FileType" }, {
    group = augroup,
    callback = function()
      if not M.state.is_open then
        return
      end

      M.follow_current_target()
    end,
  })

  -- Handle window resize
  vim.api.nvim_create_autocmd("VimResized", {
    group = augroup,
    callback = function()
      if M.state.is_open and M.state.winid and vim.api.nvim_win_is_valid(M.state.winid) then
        local opts = config.get()
        vim.api.nvim_win_set_width(M.state.winid, opts.width)
      end
    end,
  })
end

-- Check if minimap is open
-- @return boolean
function M.is_open()
  return M.state.is_open
end

return M
