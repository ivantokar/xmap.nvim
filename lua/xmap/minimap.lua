-- lua/xmap/minimap.lua
-- Minimap window and rendering logic for xmap.nvim

local config = require("xmap.config")
local highlight = require("xmap.highlight")
local treesitter = require("xmap.treesitter")
local navigation = require("xmap.navigation")

local M = {}

-- Minimap state
M.state = {
  bufnr = nil, -- Minimap buffer number
  winid = nil, -- Minimap window ID
  main_bufnr = nil, -- Main buffer being mapped
  main_winid = nil, -- Main window being mapped
  is_open = false,
  last_update = 0, -- Timestamp of last update
  update_timer = nil, -- Throttle timer
  line_mapping = {}, -- Maps minimap line numbers to source line numbers
}

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

  -- Calculate window position
  local win_opts = {
    relative = "editor",
    width = opts.width,
    height = vim.o.lines - 2, -- Full height minus command line
    row = 0,
    col = opts.side == "right" and (vim.o.columns - opts.width) or 0,
    style = "minimal",
    border = "none",
    focusable = true,
  }

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
  vim.api.nvim_win_set_option(win, "cursorline", true)
  vim.api.nvim_win_set_option(win, "wrap", false)
  vim.api.nvim_win_set_option(win, "signcolumn", "no")
  vim.api.nvim_win_set_option(win, "foldcolumn", "0")
  vim.api.nvim_win_set_option(win, "winfixwidth", true)
  vim.api.nvim_win_set_option(win, "fillchars", "eob: ") -- Remove ~ for empty lines

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
  -- File header is at the top, typically first 10 lines
  if line_nr > 15 then
    return false
  end

  -- Check if this line and surrounding lines are comments
  local comment_count = 0
  for i = 1, math.min(15, #lines) do
    local l = vim.trim(lines[i])
    if l:match("^//") or l:match("^/%*") or l:match("^%*") then
      comment_count = comment_count + 1
    end
  end

  -- If many consecutive comments at top, it's likely a file header
  return comment_count >= 3 and line_nr <= comment_count
end

-- Extract comment text (remove markers, get first line only)
-- @param line string: Comment line
-- @return string|nil, string|nil, boolean: Cleaned comment text, marker type (MARK/TODO/etc), is_doc_comment
local function extract_comment(line)
  local trimmed = vim.trim(line)

  -- Check if this is a doc comment (///)
  local is_doc_comment = trimmed:match("^///")

  -- Remove comment markers
  local text = trimmed:gsub("^///%s*", "")  -- /// doc comments
    :gsub("^//%s*", "")  -- // comments
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

  -- Calculate relative position
  local distance = line_nr - current_line
  local arrow = ""

  if distance < 0 then
    arrow = "↑"
    distance = math.abs(distance)
  elseif distance > 0 then
    arrow = "↓"
  else
    arrow = "→"
    distance = 0
  end

  -- Format: arrow + number (3 digits) + space
  local prefix = string.format("%s%3d ", arrow, distance)

  local trimmed = vim.trim(line)

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
    -- This is a function/class/struct - show it with entity name
    local navigation = require("xmap.navigation")
    local entity, keyword = navigation.get_entity_at_line(main_bufnr, line_nr)

    if entity or structural_text then
      return prefix .. icon .. " " .. (entity or structural_text)
    else
      -- Fallback: show trimmed line
      local compact = trimmed:gsub("%s+", " ")
      local max_len = opts.render.max_line_length or 40
      if #compact > max_len then
        compact = compact:sub(1, max_len - 3) .. "..."
      end
      return prefix .. icon .. " " .. compact
    end
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
-- @return table, table: Lines for minimap, line number mapping
function M.render_buffer(main_bufnr, main_winid)
  if not vim.api.nvim_buf_is_valid(main_bufnr) then
    return {}, {}
  end

  -- Get current line in main buffer
  local navigation = require("xmap.navigation")
  local current_line = navigation.get_main_cursor_line(main_winid)

  local lines = vim.api.nvim_buf_get_lines(main_bufnr, 0, -1, false)
  local rendered = {}
  local line_mapping = {}  -- Maps minimap line number to source line number
  local nodes_by_line = {}

  -- Build structural lookup once per render
  local filetype = vim.api.nvim_buf_get_option(main_bufnr, "filetype")
  if config.is_treesitter_enabled(filetype) then
    local nodes = treesitter.get_structural_nodes(main_bufnr, filetype)
    for _, node in ipairs(nodes) do
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

  return rendered, line_mapping
end

-- Apply highlighting for relative numbers, arrows, icons, and comments
-- @param minimap_bufnr number: Minimap buffer
-- @param main_bufnr number: Main buffer
-- @param main_winid number: Main window
function M.apply_relative_number_highlighting(minimap_bufnr, main_bufnr, main_winid)
  if not vim.api.nvim_buf_is_valid(minimap_bufnr) or not vim.api.nvim_buf_is_valid(main_bufnr) then
    return
  end

  -- Clear previous highlights
  highlight.clear(minimap_bufnr, M.ns_syntax)

  -- Get current line
  local navigation = require("xmap.navigation")
  local current_line = navigation.get_main_cursor_line(main_winid)

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

    -- Highlight arrow (position 0)
    if distance < 0 then
      highlight.apply(minimap_bufnr, M.ns_syntax, "XmapRelativeUp", minimap_line_nr - 1, 0, 1)
    elseif distance > 0 then
      highlight.apply(minimap_bufnr, M.ns_syntax, "XmapRelativeDown", minimap_line_nr - 1, 0, 1)
    else
      highlight.apply(minimap_bufnr, M.ns_syntax, "XmapRelativeCurrent", minimap_line_nr - 1, 0, 1)
    end

    -- Highlight number (after arrow, includes space before content)
    -- Format is: "↑  0 " or "↑ 42 " - positions 1-5 cover the number and trailing space
    highlight.apply(minimap_bufnr, M.ns_syntax, "XmapRelativeNumber", minimap_line_nr - 1, 1, 5)

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
    elseif line_text:match("^.%s*%d+ ///") then
      -- Doc comment
      local start_pos = line_text:find("///")
      if start_pos then
        highlight.apply(minimap_bufnr, M.ns_syntax, "XmapCommentDoc", minimap_line_nr - 1, start_pos - 1, -1)
      end
    elseif line_text:match("^.%s*%d+ //") then
      -- Regular comment
      local start_pos = line_text:find("//")
      if start_pos then
        highlight.apply(minimap_bufnr, M.ns_syntax, "XmapCommentNormal", minimap_line_nr - 1, start_pos - 1, -1)
      end
    else
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
function M.apply_syntax_highlighting(minimap_bufnr, main_bufnr)
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
  local nodes = treesitter.get_structural_nodes(main_bufnr, filetype)

  -- Apply highlights for each structural node (only if rendered in minimap)
  for _, node in ipairs(nodes) do
    local hl_group = treesitter.get_highlight_for_type(node.type)

    -- Minimaps render only key structural lines, so highlight the start line if present
    local source_line = node.start_line + 1 -- convert to 1-indexed
    local minimap_line = line_lookup[source_line]
    if minimap_line then
      highlight.apply(minimap_bufnr, M.ns_structure, hl_group, minimap_line - 1, 0, -1)
    end
  end

  -- Heuristic fallback when no nodes are returned (e.g., parser missing)
  if #nodes == 0 then
    local lines = vim.api.nvim_buf_get_lines(main_bufnr, 0, -1, false)
    for minimap_line, source_line in pairs(line_lookup) do
      local text = lines[source_line] or ""

      -- Basic Lua function detection: function foo(...) or local function foo(...)
      if filetype == "lua" then
        if text:match("^%s*local%s+function%s+[%w_%.:]+") or text:match("^%s*function%s+[%w_%.:]+") then
          highlight.apply(minimap_bufnr, M.ns_structure, "XmapFunction", minimap_line - 1, 0, -1)
        end
      end
    end
  end
end

-- Highlight the visible viewport in minimap
-- @param minimap_bufnr number: Minimap buffer
-- @param main_winid number: Main window
function M.highlight_viewport(minimap_bufnr, main_winid)
  if not vim.api.nvim_buf_is_valid(minimap_bufnr) or not vim.api.nvim_win_is_valid(main_winid) then
    return
  end

  -- Clear previous viewport highlights
  highlight.clear(minimap_bufnr, M.ns_viewport)

  -- Get visible range in main window
  local range = navigation.get_visible_range(main_winid)

  -- Highlight visible lines in minimap
  for line = range.start - 1, range["end"] - 1 do
    highlight.apply(minimap_bufnr, M.ns_viewport, "XmapViewport", line, 0, -1)
  end
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
  local rendered_lines, line_mapping = M.render_buffer(M.state.main_bufnr, M.state.main_winid)

  -- Store line mapping for navigation
  M.state.line_mapping = line_mapping

  -- Update minimap buffer
  vim.api.nvim_buf_set_option(M.state.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(M.state.bufnr, 0, -1, false, rendered_lines)
  vim.api.nvim_buf_set_option(M.state.bufnr, "modifiable", false)

  -- Apply syntax highlighting for arrows, numbers, icons, and structure
  M.apply_relative_number_highlighting(M.state.bufnr, M.state.main_bufnr, M.state.main_winid)
  M.apply_syntax_highlighting(M.state.bufnr, M.state.main_bufnr)

  -- Update minimap cursor to follow main buffer (viewport highlighting disabled for now)
  if M.state.main_winid and vim.api.nvim_win_is_valid(M.state.main_winid) then
    local main_line = navigation.get_main_cursor_line(M.state.main_winid)
    if M.state.winid and vim.api.nvim_win_is_valid(M.state.winid) then
      navigation.update_minimap_cursor(M.state.winid, main_line)
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

  -- Clear timers
  if M.state.update_timer then
    M.state.update_timer:stop()
    M.state.update_timer = nil
  end

  -- Clear autocommands
  pcall(vim.api.nvim_del_augroup_by_name, "XmapUpdate")

  -- Close window
  if M.state.winid and vim.api.nvim_win_is_valid(M.state.winid) then
    vim.api.nvim_win_close(M.state.winid, true)
  end

  -- Delete buffer
  if M.state.bufnr and vim.api.nvim_buf_is_valid(M.state.bufnr) then
    vim.api.nvim_buf_delete(M.state.bufnr, { force = true })
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
      -- Clear navigation virtual text when moving in main buffer
      local navigation = require("xmap.navigation")
      if M.state.bufnr and vim.api.nvim_buf_is_valid(M.state.bufnr) then
        vim.api.nvim_buf_clear_namespace(M.state.bufnr, navigation.ns_relative, 0, -1)
        -- Fast path: only refresh relative markers to avoid re-rendering entire buffer on every move
        if M.state.line_mapping and #M.state.line_mapping > 0 then
          M.apply_relative_number_highlighting(M.state.bufnr, M.state.main_bufnr, M.state.main_winid)
          return
        end
      end

      -- Fallback to full update if mapping missing
      M.throttled_update()
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
      M.close()
    end,
  })

  -- Also close if buffer becomes invalid (extra safety check)
  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    group = augroup,
    callback = function()
      if M.state.is_open and M.state.main_bufnr then
        if not vim.api.nvim_buf_is_valid(M.state.main_bufnr) then
          M.close()
        end
      end
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
