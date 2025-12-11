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

-- Calculate code density for a line
-- @param line string: Line content
-- @return number: Density value 0-1
function M.calculate_density(line)
  local trimmed = vim.trim(line)
  if #trimmed == 0 then
    return 0
  end

  -- Count non-whitespace characters
  local non_ws = trimmed:gsub("%s+", "")
  return #non_ws / math.max(#line, 1)
end

-- Render a block representing multiple source lines
-- @param lines table: Source lines in this block
-- @param block_info table: Additional info (has functions, etc.)
-- @return string: Rendered block line
function M.render_block(lines, block_info)
  local opts = config.get()

  if #lines == 0 then
    return string.rep(" ", opts.width - 2)
  end

  -- Calculate average density for this block
  local total_density = 0
  local non_empty = 0

  for _, line in ipairs(lines) do
    local density = M.calculate_density(line)
    if density > 0 then
      total_density = total_density + density
      non_empty = non_empty + 1
    end
  end

  local avg_density = non_empty > 0 and (total_density / non_empty) or 0

  -- Choose block character based on density
  local char
  if avg_density > 0.6 then
    char = "█"
  elseif avg_density > 0.4 then
    char = "▓"
  elseif avg_density > 0.2 then
    char = "▒"
  elseif avg_density > 0 then
    char = "░"
  else
    char = " "
  end

  return string.rep(char, opts.width - 2)
end

-- Render entire buffer content for minimap with scaling
-- @param main_bufnr number: Main buffer to render
-- @param minimap_height number: Target height for minimap
-- @return table: {lines = {}, mapping = {}}
function M.render_buffer(main_bufnr, minimap_height)
  if not vim.api.nvim_buf_is_valid(main_bufnr) then
    return { lines = {}, mapping = {} }
  end

  local source_lines = vim.api.nvim_buf_get_lines(main_bufnr, 0, -1, false)
  local total_source_lines = #source_lines

  if total_source_lines == 0 then
    return { lines = {}, mapping = {} }
  end

  local rendered = {}
  local mapping = {}  -- mapping[minimap_line] = {start_line, end_line}

  -- Calculate how many source lines per minimap line
  local lines_per_block = math.max(1, math.ceil(total_source_lines / minimap_height))

  local minimap_line = 1
  local source_idx = 1

  while source_idx <= total_source_lines and minimap_line <= minimap_height do
    -- Get lines for this block
    local block_start = source_idx
    local block_end = math.min(source_idx + lines_per_block - 1, total_source_lines)

    local block_lines = {}
    for i = block_start, block_end do
      table.insert(block_lines, source_lines[i])
    end

    -- Render this block
    rendered[minimap_line] = M.render_block(block_lines, {})
    mapping[minimap_line] = { start_line = block_start, end_line = block_end }

    minimap_line = minimap_line + 1
    source_idx = block_end + 1
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

  -- Get structural nodes from Tree-sitter
  local nodes = treesitter.get_structural_nodes(main_bufnr, filetype)

  -- For each minimap line, check if it contains structural nodes
  for minimap_line, range in pairs(mapping) do
    for _, node in ipairs(nodes) do
      -- Check if node overlaps with this block
      if node.start_line <= range.end_line and node.end_line >= range.start_line then
        local hl_group = treesitter.get_highlight_for_type(node.type)
        highlight.apply(minimap_bufnr, M.ns_syntax, hl_group, minimap_line - 1, 0, -1)
        break -- Only apply one highlight per line
      end
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

  -- Get minimap window height
  local minimap_height = 50  -- default
  if M.state.winid and vim.api.nvim_win_is_valid(M.state.winid) then
    minimap_height = vim.api.nvim_win_get_height(M.state.winid)
  end

  -- Render buffer content with scaling
  local result = M.render_buffer(M.state.main_bufnr, minimap_height)
  M.state.line_mapping = result.mapping

  -- Update minimap buffer
  vim.api.nvim_buf_set_option(M.state.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(M.state.bufnr, 0, -1, false, result.lines)
  vim.api.nvim_buf_set_option(M.state.bufnr, "modifiable", false)

  -- Apply syntax highlighting
  M.apply_syntax_highlighting(M.state.bufnr, M.state.main_bufnr, M.state.line_mapping)

  -- Highlight viewport and cursor
  if M.state.main_winid and vim.api.nvim_win_is_valid(M.state.main_winid) then
    M.highlight_viewport(M.state.bufnr, M.state.main_winid, M.state.line_mapping)
    M.highlight_cursor(M.state.bufnr, M.state.main_winid, M.state.line_mapping)

    -- Update minimap cursor position to match current editor line
    local main_line = navigation.get_main_cursor_line(M.state.main_winid)
    local minimap_line = M.source_to_minimap_line(main_line, M.state.line_mapping)

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
