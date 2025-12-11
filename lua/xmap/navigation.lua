-- lua/xmap/navigation.lua
-- Navigation and jumping logic for xmap.nvim

local config = require("xmap.config")

local M = {}

-- State tracking
M.state = {
  minimap_cursor_line = 1, -- Current line in minimap (1-indexed)
  last_jump_line = nil, -- Last line jumped to
}

-- Get current line in main buffer
-- @param winid number: Window ID of main buffer
-- @return number: Current line (1-indexed)
function M.get_main_cursor_line(winid)
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return 1
  end

  local cursor = vim.api.nvim_win_get_cursor(winid)
  return cursor[1]
end

-- Calculate relative line distance and direction
-- @param from_line number: Starting line (1-indexed)
-- @param to_line number: Target line (1-indexed)
-- @return table: { distance = number, direction = "up"|"down"|"current" }
function M.calculate_relative_position(from_line, to_line)
  local distance = to_line - from_line
  local direction = "current"

  if distance > 0 then
    direction = "down"
  elseif distance < 0 then
    direction = "up"
    distance = math.abs(distance)
  else
    distance = 0
  end

  return {
    distance = distance,
    direction = direction,
  }
end

-- Show relative line indicator
-- @param main_line number: Current line in main buffer (1-indexed)
-- @param target_line number: Target line to jump to (1-indexed)
function M.show_relative_indicator(main_line, target_line)
  local opts = config.get()

  if not opts.navigation.show_relative_line then
    return
  end

  local rel = M.calculate_relative_position(main_line, target_line)

  -- Format message with arrow, distance, and actual line number
  local message
  if rel.direction == "current" then
    message = string.format("Line %d (current)", target_line)
  elseif rel.direction == "up" then
    message = string.format("↑ %d lines → line %d", rel.distance, target_line)
  else
    message = string.format("↓ %d lines → line %d", rel.distance, target_line)
  end

  -- Display based on indicator mode
  if opts.navigation.indicator_mode == "notify" then
    vim.notify(message, vim.log.levels.INFO)
  elseif opts.navigation.indicator_mode == "float" then
    -- Create a small floating window
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { message })

    local width = #message + 2
    local height = 1

    local win_opts = {
      relative = "cursor",
      row = 1,
      col = 0,
      width = width,
      height = height,
      style = "minimal",
      border = "rounded",
    }

    local win = vim.api.nvim_open_win(buf, false, win_opts)

    -- Auto-close after a short delay
    vim.defer_fn(function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end, 1500)
  end
  -- "virtual" mode would be implemented in minimap.lua with virtual text
end

-- Jump from minimap to main buffer
-- @param minimap_bufnr number: Minimap buffer number
-- @param minimap_winid number: Minimap window ID
-- @param main_bufnr number: Main buffer number
-- @param main_winid number: Main window ID
-- @param line_mapping table: Mapping from minimap lines to source line ranges
function M.jump_to_line(minimap_bufnr, minimap_winid, main_bufnr, main_winid, line_mapping)
  if not vim.api.nvim_win_is_valid(minimap_winid) or not vim.api.nvim_win_is_valid(main_winid) then
    return
  end

  -- Get current cursor position in minimap
  local cursor = vim.api.nvim_win_get_cursor(minimap_winid)
  local minimap_line = cursor[1]

  -- Get the source line range for this minimap line
  local target_line = minimap_line  -- Default fallback
  if line_mapping and line_mapping[minimap_line] then
    -- Jump to the middle of the block range
    local range = line_mapping[minimap_line]
    target_line = math.floor((range.start_line + range.end_line) / 2)
  end

  -- Get total lines in main buffer
  local main_line_count = vim.api.nvim_buf_line_count(main_bufnr)

  -- Clamp to valid range
  target_line = math.max(1, math.min(target_line, main_line_count))

  -- Show relative indicator with arrow and line number
  local current_main_line = M.get_main_cursor_line(main_winid)
  M.show_relative_indicator(current_main_line, target_line)

  -- Jump to the line in main buffer
  vim.api.nvim_win_set_cursor(main_winid, { target_line, 0 })

  -- Center the view if configured
  local opts = config.get()
  if opts.navigation.auto_center then
    vim.api.nvim_win_call(main_winid, function()
      vim.cmd("normal! zz")
    end)
  end

  -- Focus main window
  vim.api.nvim_set_current_win(main_winid)

  -- Store last jump
  M.state.last_jump_line = target_line
end

-- Update minimap cursor to follow main buffer
-- @param minimap_winid number: Minimap window ID
-- @param main_line number: Current line in main buffer (1-indexed)
function M.update_minimap_cursor(minimap_winid, main_line)
  if not vim.api.nvim_win_is_valid(minimap_winid) then
    return
  end

  -- Set cursor in minimap to match main buffer line
  pcall(vim.api.nvim_win_set_cursor, minimap_winid, { main_line, 0 })
  M.state.minimap_cursor_line = main_line
end

-- Focus the minimap window
-- @param minimap_winid number: Minimap window ID
function M.focus_minimap(minimap_winid)
  if not minimap_winid or not vim.api.nvim_win_is_valid(minimap_winid) then
    vim.notify("Minimap window not found", vim.log.levels.WARN)
    return
  end

  vim.api.nvim_set_current_win(minimap_winid)
end

-- Get visible line range in main window
-- @param winid number: Window ID
-- @return table: { start = number, end = number } (1-indexed)
function M.get_visible_range(winid)
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return { start = 1, ["end"] = 1 }
  end

  local info = vim.fn.getwininfo(winid)[1]
  if not info then
    return { start = 1, ["end"] = 1 }
  end

  return {
    start = info.topline,
    ["end"] = info.botline,
  }
end

-- Set up keymaps for minimap buffer
-- @param minimap_bufnr number: Minimap buffer number
-- @param minimap_winid number: Minimap window ID
-- @param main_bufnr number: Main buffer number
-- @param main_winid number: Main window ID
function M.setup_minimap_keymaps(minimap_bufnr, minimap_winid, main_bufnr, main_winid)
  local opts = config.get()

  -- Get line mapping from minimap state
  local get_line_mapping = function()
    local minimap = require("xmap.minimap")
    return minimap.state.line_mapping or {}
  end

  -- Jump to line mapping
  if opts.keymaps.jump then
    vim.keymap.set("n", opts.keymaps.jump, function()
      M.jump_to_line(minimap_bufnr, minimap_winid, main_bufnr, main_winid, get_line_mapping())
    end, { buffer = minimap_bufnr, silent = true, desc = "Jump to line" })
  end

  -- Close minimap mapping
  if opts.keymaps.close then
    vim.keymap.set("n", opts.keymaps.close, function()
      require("xmap").close()
    end, { buffer = minimap_bufnr, silent = true, desc = "Close minimap" })
  end

  -- Note: Removed CursorMoved autocmd to prevent notification spam
  -- Relative position indicator now only shows when jumping (pressing Enter)
end

return M
