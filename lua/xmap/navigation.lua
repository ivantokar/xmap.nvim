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

-- Extract entity name from Swift code line with keyword
-- @param line_text string: The line of code
-- @return string|nil, string|nil: Entity name, keyword type
local function extract_swift_name(line_text)
  -- Remove leading/trailing whitespace and access modifiers
  local cleaned = line_text:gsub("^%s*", ""):gsub("^public%s+", ""):gsub("^private%s+", ""):gsub("^internal%s+", "")

  -- Swift function: func name( or func name<T>(
  local name = cleaned:match("^func%s+([%w_]+)")
  if name then return name, "func" end

  -- Swift init
  if cleaned:match("^init%s*%(") or cleaned:match("^init%s*<") then
    return "init", "func"
  end

  -- Swift deinit
  if cleaned:match("^deinit%s*{") then
    return "deinit", "func"
  end

  -- Class/Struct/Enum/Protocol: class Name, struct Name, etc.
  name = cleaned:match("^class%s+([%w_]+)")
  if name then return name, "class" end

  name = cleaned:match("^struct%s+([%w_]+)")
  if name then return name, "struct" end

  name = cleaned:match("^enum%s+([%w_]+)")
  if name then return name, "enum" end

  name = cleaned:match("^protocol%s+([%w_]+)")
  if name then return name, "protocol" end

  -- Properties: let name: or var name:
  name = cleaned:match("^let%s+([%w_]+)%s*:")
  if name then return name, "let" end

  name = cleaned:match("^var%s+([%w_]+)%s*:")
  if name then return name, "var" end

  return nil, nil
end

-- Get entity name at line (function/class name) with keyword
-- @param bufnr number: Buffer number
-- @param line number: Line number (1-indexed)
-- @return string|nil, string|nil: Full declaration (keyword + name), keyword type
function M.get_entity_at_line(bufnr, line)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil, nil
  end

  -- Only process Swift files
  local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")
  if filetype ~= "swift" then
    return nil, nil
  end

  local treesitter = require("xmap.treesitter")
  local nodes = treesitter.get_structural_nodes(bufnr, filetype)

  -- Find the node at this line
  for _, node in ipairs(nodes) do
    if node.start_line + 1 == line then
      -- Get the actual line text
      local lines = vim.api.nvim_buf_get_lines(bufnr, node.start_line, node.start_line + 1, false)
      if #lines > 0 then
        local name, keyword = extract_swift_name(lines[1])
        if name and keyword then
          -- Return "func name", "class name", "let name", etc.
          return keyword .. " " .. name, keyword
        end
      end
    end
  end

  return nil, nil
end

-- Namespace for relative indicator
M.ns_relative = vim.api.nvim_create_namespace("xmap_relative_indicator")

-- Show relative line indicator as virtual text in minimap
-- @param minimap_bufnr number: Minimap buffer
-- @param minimap_line number: Line in minimap (1-indexed)
-- @param main_line number: Current line in main buffer (1-indexed)
-- @param target_line number: Target line in minimap (1-indexed)
-- @param main_bufnr number: Main buffer number (for entity detection)
function M.show_relative_indicator(minimap_bufnr, minimap_line, main_line, target_line, main_bufnr)
  local opts = config.get()

  if not opts.navigation.show_relative_line then
    return
  end

  if not vim.api.nvim_buf_is_valid(minimap_bufnr) then
    return
  end

  -- Clear previous indicators
  vim.api.nvim_buf_clear_namespace(minimap_bufnr, M.ns_relative, 0, -1)

  local rel = M.calculate_relative_position(main_line, target_line)

  -- Build virtual text chunks with highlights
  local virt_text = {}

  if rel.direction == "current" then
    -- Just show the line normally, maybe with a subtle indicator
    return
  elseif rel.direction == "up" then
    -- Green arrow
    table.insert(virt_text, { "↑ ", "XmapRelativeUp" })
    -- Dimmed number
    table.insert(virt_text, { tostring(rel.distance) .. " ", "XmapRelativeNumber" })
  else -- down
    -- Red arrow
    table.insert(virt_text, { "↓ ", "XmapRelativeDown" })
    -- Dimmed number
    table.insert(virt_text, { tostring(rel.distance) .. " ", "XmapRelativeNumber" })
  end

  -- Add virtual text to the current line in minimap
  pcall(vim.api.nvim_buf_set_extmark, minimap_bufnr, M.ns_relative, minimap_line - 1, 0, {
    virt_text = virt_text,
    virt_text_pos = "eol", -- End of line
    hl_mode = "combine",
  })
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

  -- Get line mapping from minimap state
  local minimap = require("xmap.minimap")
  local line_mapping = minimap.state.line_mapping

  -- Map minimap line to actual source line
  local target_line = line_mapping[minimap_line] or minimap_line

  -- Get total lines in main buffer
  local main_line_count = vim.api.nvim_buf_line_count(main_bufnr)

  -- Clamp to valid range
  target_line = math.max(1, math.min(target_line, main_line_count))

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

  -- Show relative indicators when navigating in minimap
  if opts.navigation.show_relative_line then
    vim.api.nvim_create_autocmd("CursorMoved", {
      buffer = minimap_bufnr,
      callback = function()
        local minimap_cursor = vim.api.nvim_win_get_cursor(minimap_winid)
        local minimap_line = minimap_cursor[1]
        local main_cursor = vim.api.nvim_win_get_cursor(main_winid)
        local main_line = main_cursor[1]

        -- Get the target line from line mapping
        local minimap = require("xmap.minimap")
        local target_line = minimap.state.line_mapping[minimap_line] or minimap_line

        M.show_relative_indicator(minimap_bufnr, minimap_line, main_line, target_line, main_bufnr)
      end,
    })

    -- Clear indicators when leaving minimap window
    vim.api.nvim_create_autocmd("WinLeave", {
      buffer = minimap_bufnr,
      callback = function()
        vim.api.nvim_buf_clear_namespace(minimap_bufnr, M.ns_relative, 0, -1)
      end,
    })
  end
end

return M
