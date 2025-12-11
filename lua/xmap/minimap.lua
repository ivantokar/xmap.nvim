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
  line_mapping = {}, -- Maps minimap line to source line range
}

-- Namespace for highlights
M.ns_viewport = highlight.create_namespace("viewport")
M.ns_cursor = highlight.create_namespace("cursor")
M.ns_syntax = highlight.create_namespace("syntax")

-- Create minimap buffer
-- @return number: Buffer number
function M.create_buffer()
  local buf = vim.api.nvim_create_buf(false, true) -- No file, scratch buffer

  -- Set buffer options
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "swapfile", false)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "buflisted", false)
  vim.api.nvim_buf_set_option(buf, "filetype", "xmap")
  vim.api.nvim_buf_set_name(buf, "xmap://minimap")

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

  -- Return to original window
  vim.api.nvim_set_current_win(current_win)

  return win
end

-- Extract node name from Tree-sitter node
-- @param node TSNode: Tree-sitter node
-- @param bufnr number: Buffer number
-- @return string: Node name or empty string
function M.get_node_name(node, bufnr)
  if not node then
    return ""
  end

  -- Check if we have the get_node_text function (Neovim 0.9+)
  local has_get_text = vim.treesitter.get_node_text ~= nil

  if not has_get_text then
    -- Fallback for older Neovim versions
    return node:type()
  end

  -- Try to get the name from child nodes
  for child in node:iter_children() do
    local type = child:type()
    if type == "identifier" or type == "simple_identifier" or type == "type_identifier" then
      local ok, name = pcall(vim.treesitter.get_node_text, child, bufnr)
      if ok and name then
        return name
      end
    end
  end

  -- Fallback: try to get text from the node itself (first 30 chars)
  local ok, text = pcall(vim.treesitter.get_node_text, node, bufnr)
  if ok and text then
    local first_line = text:match("([^\n]*)")
    if first_line then
      -- Clean up the text
      first_line = vim.trim(first_line)
      -- Truncate if too long
      if #first_line > 30 then
        return first_line:sub(1, 27) .. "..."
      end
      return first_line
    end
  end

  return ""
end

-- Calculate relative line indicator
-- @param current_line number: Current cursor line
-- @param target_line number: Target line
-- @return string: Formatted indicator like "[↓ 5]" or "[↑ 15]"
function M.format_relative_indicator(current_line, target_line)
  local distance = target_line - current_line

  if distance == 0 then
    return "[•]"
  elseif distance > 0 then
    return string.format("[↓ %d]", distance)
  else
    return string.format("[↑ %d]", math.abs(distance))
  end
end

-- Render minimap with structure names and relative indicators
-- @param main_bufnr number: Main buffer to render
-- @param current_line number: Current cursor line in main buffer
-- @param minimap_height number: Target height for minimap
-- @return table: {lines = {}, mapping = {}}
function M.render_buffer(main_bufnr, current_line, minimap_height)
  if not vim.api.nvim_buf_is_valid(main_bufnr) then
    return { lines = {}, mapping = {} }
  end

  local opts = config.get()
  local filetype = vim.api.nvim_buf_get_option(main_bufnr, "filetype")

  -- Get structural nodes from Tree-sitter (including MARK comments for Swift)
  local nodes = {}
  if config.is_treesitter_enabled(filetype) then
    if filetype == "swift" then
      nodes = treesitter.get_swift_structure(main_bufnr, filetype)
    else
      nodes = treesitter.get_structural_nodes(main_bufnr, filetype)
    end
  end

  local rendered = {}
  local mapping = {}

  if #nodes == 0 then
    -- Fallback: show line-based overview
    local source_lines = vim.api.nvim_buf_get_lines(main_bufnr, 0, -1, false)
    local total_source_lines = #source_lines

    if total_source_lines == 0 then
      return { lines = {}, mapping = {} }
    end

    -- Show every Nth line
    local lines_per_block = math.max(1, math.ceil(total_source_lines / minimap_height))

    local minimap_line = 1
    for i = 1, total_source_lines, lines_per_block do
      local line_text = vim.trim(source_lines[i])
      if #line_text > 25 then
        line_text = line_text:sub(1, 22) .. "..."
      end

      local indicator = M.format_relative_indicator(current_line, i)
      rendered[minimap_line] = string.format("%-25s %s", line_text, indicator)
      mapping[minimap_line] = { start_line = i, end_line = i }

      minimap_line = minimap_line + 1
    end
  else
    -- Show structural elements with names and indicators
    for i, node in ipairs(nodes) do
      if i > minimap_height then
        break
      end

      local display_name
      local node_line = node.start_line + 1 -- Convert to 1-indexed

      -- Handle MARK comments specially
      if node.type == "mark" then
        -- MARK comments are shown as section headers
        display_name = "━ " .. node.mark_text
      else
        -- Get node name for regular structural elements
        local name = M.get_node_name(node.node, main_bufnr)
        if name == "" then
          name = node.type
        end

        -- Add indentation based on nesting (approximate)
        local indent = ""
        local depth = 0
        -- Simple heuristic: deeper nodes have larger line ranges that are contained in others
        for _, other_node in ipairs(nodes) do
          if other_node ~= node and
             other_node.type ~= "mark" and
             other_node.start_line <= node.start_line and
             other_node.end_line >= node.end_line and
             (other_node.end_line - other_node.start_line) > (node.end_line - node.start_line) then
            depth = depth + 1
          end
        end
        depth = math.min(depth, 4) -- Max 4 levels of indentation
        indent = string.rep("  ", depth)

        display_name = indent .. name
      end

      -- Format the line
      local max_name_length = opts.width - 10 -- Leave space for indicator

      if #display_name > max_name_length then
        display_name = display_name:sub(1, max_name_length - 3) .. "..."
      end

      -- Calculate relative indicator
      local indicator = M.format_relative_indicator(current_line, node_line)

      -- Format with padding
      local line = string.format("%-" .. max_name_length .. "s %s", display_name, indicator)

      rendered[i] = line
      mapping[i] = { start_line = node_line, end_line = node.end_line + 1, node_type = node.type }
    end
  end

  return { lines = rendered, mapping = mapping }
end

-- Apply syntax highlighting based on Tree-sitter
-- @param minimap_bufnr number: Minimap buffer
-- @param main_bufnr number: Main buffer
-- @param mapping table: Line mapping
function M.apply_syntax_highlighting(minimap_bufnr, main_bufnr, mapping)
  if not vim.api.nvim_buf_is_valid(minimap_bufnr) or not vim.api.nvim_buf_is_valid(main_bufnr) then
    return
  end

  local opts = config.get()
  local filetype = vim.api.nvim_buf_get_option(main_bufnr, "filetype")

  if not opts.treesitter.highlight_scopes or not config.is_treesitter_enabled(filetype) then
    return
  end

  -- Clear previous syntax highlights
  highlight.clear(minimap_bufnr, M.ns_syntax)

  -- Apply highlights based on node_type stored in mapping
  for minimap_line, range in pairs(mapping) do
    if range.node_type then
      local hl_group = treesitter.get_highlight_for_type(range.node_type)
      highlight.apply(minimap_bufnr, M.ns_syntax, hl_group, minimap_line - 1, 0, -1)
    end
  end
end

-- Find minimap line for a given source line
-- @param source_line number: Source line number (1-indexed)
-- @param mapping table: Line mapping
-- @return number|nil: Minimap line or nil
function M.source_to_minimap_line(source_line, mapping)
  for minimap_line, range in pairs(mapping) do
    if source_line >= range.start_line and source_line <= range.end_line then
      return minimap_line
    end
  end
  return nil
end

-- Highlight the visible viewport in minimap
-- @param minimap_bufnr number: Minimap buffer
-- @param main_winid number: Main window
-- @param mapping table: Line mapping
function M.highlight_viewport(minimap_bufnr, main_winid, mapping)
  if not vim.api.nvim_buf_is_valid(minimap_bufnr) or not vim.api.nvim_win_is_valid(main_winid) then
    return
  end

  -- Clear previous viewport highlights
  highlight.clear(minimap_bufnr, M.ns_viewport)

  -- Get visible range in main window
  local range = navigation.get_visible_range(main_winid)

  -- Find corresponding minimap lines
  local start_minimap = M.source_to_minimap_line(range.start, mapping)
  local end_minimap = M.source_to_minimap_line(range["end"], mapping)

  if start_minimap and end_minimap then
    for line = start_minimap - 1, end_minimap - 1 do
      highlight.apply(minimap_bufnr, M.ns_viewport, "XmapViewport", line, 0, -1)
    end
  end
end

-- Highlight current cursor position in minimap
-- @param minimap_bufnr number: Minimap buffer
-- @param main_winid number: Main window
-- @param mapping table: Line mapping
function M.highlight_cursor(minimap_bufnr, main_winid, mapping)
  if not vim.api.nvim_buf_is_valid(minimap_bufnr) or not vim.api.nvim_win_is_valid(main_winid) then
    return
  end

  -- Clear previous cursor highlights
  highlight.clear(minimap_bufnr, M.ns_cursor)

  -- Get current line in main window
  local main_line = navigation.get_main_cursor_line(main_winid)

  -- Find corresponding minimap line
  local minimap_line = M.source_to_minimap_line(main_line, mapping)

  if minimap_line then
    highlight.apply(minimap_bufnr, M.ns_cursor, "XmapCursor", minimap_line - 1, 0, -1)
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

  -- Get current cursor line in main buffer
  local current_line = 1
  if M.state.main_winid and vim.api.nvim_win_is_valid(M.state.main_winid) then
    current_line = navigation.get_main_cursor_line(M.state.main_winid)
  end

  -- Get minimap window height
  local minimap_height = 50  -- default
  if M.state.winid and vim.api.nvim_win_is_valid(M.state.winid) then
    minimap_height = vim.api.nvim_win_get_height(M.state.winid)
  end

  -- Render buffer content with current line for relative indicators
  local result = M.render_buffer(M.state.main_bufnr, current_line, minimap_height)
  M.state.line_mapping = result.mapping

  -- Update minimap buffer
  vim.api.nvim_buf_set_option(M.state.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(M.state.bufnr, 0, -1, false, result.lines)
  vim.api.nvim_buf_set_option(M.state.bufnr, "modifiable", false)

  -- Apply syntax highlighting
  M.apply_syntax_highlighting(M.state.bufnr, M.state.main_bufnr, M.state.line_mapping)

  -- Highlight current item in minimap (the one closest to cursor)
  if M.state.main_winid and vim.api.nvim_win_is_valid(M.state.main_winid) then
    M.highlight_cursor(M.state.bufnr, M.state.main_winid, M.state.line_mapping)

    -- Update minimap cursor position to match current editor line
    local minimap_line = M.source_to_minimap_line(current_line, M.state.line_mapping)

    if minimap_line and M.state.winid and vim.api.nvim_win_is_valid(M.state.winid) then
      pcall(vim.api.nvim_win_set_cursor, M.state.winid, { minimap_line, 0 })
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

  -- Close minimap when main buffer is closed
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = augroup,
    buffer = M.state.main_bufnr,
    callback = function()
      M.close()
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
