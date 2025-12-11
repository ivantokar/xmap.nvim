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
-- @param target_line number: Target line in minimap (1-indexed)
function M.show_relative_indicator(main_line, target_line)
  local opts = config.get()

  if not opts.navigation.show_relative_line then
    return
  end

  local rel = M.calculate_relative_position(main_line, target_line)

  -- Format message
  local message
  if rel.direction == "current" then
    message = "Current line"
  elseif rel.direction == "up" then
    message = string.format("↑ %d lines above", rel.distance)
  else
    message = string.format("↓ %d lines below", rel.distance)
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
function M.jump_to_line(minimap_bufnr, minimap_winid, main_bufnr, main_winid)
  if not vim.api.nvim_win_is_valid(minimap_winid) or not vim.api.nvim_win_is_valid(main_winid) then
    return
  end

  -- Get current cursor position in minimap
  local cursor = vim.api.nvim_win_get_cursor(minimap_winid)
  local minimap_line = cursor[1]

  -- The minimap line corresponds directly to the main buffer line
  -- (we render 1:1 in our implementation)
  local target_line = minimap_line

  -- Get total lines in main buffer
  local main_line_count = vim.api.nvim_buf_line_count(main_bufnr)

  -- Clamp to valid range
  target_line = math.max(1, math.min(target_line, main_line_count))

  -- Show relative indicator
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

  -- Jump to line mapping
  if opts.keymaps.jump then
    vim.keymap.set("n", opts.keymaps.jump, function()
      M.jump_to_line(minimap_bufnr, minimap_winid, main_bufnr, main_winid)
    end, { buffer = minimap_bufnr, silent = true, desc = "Jump to line" })
  end

  -- Close minimap mapping
  if opts.keymaps.close then
    vim.keymap.set("n", opts.keymaps.close, function()
      require("xmap").close()
    end, { buffer = minimap_bufnr, silent = true, desc = "Close minimap" })
  end

  -- Show relative position on cursor move
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = minimap_bufnr,
    callback = function()
      local cursor = vim.api.nvim_win_get_cursor(minimap_winid)
      local minimap_line = cursor[1]
      local main_line = M.get_main_cursor_line(main_winid)

      M.show_relative_indicator(main_line, minimap_line)
    end,
  })
end

return M
