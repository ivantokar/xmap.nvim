-- PURPOSE:
-- - Own jumps and cursor sync between minimap and source window.
-- CONSTRAINTS:
-- - Resolve all navigation through `line_mapping` when available.

local config = require("xmap.config")

local M = {}

local function clamp(value, min_value, max_value)
  return math.max(min_value, math.min(value, max_value))
end
M.state = {
  minimap_cursor_line = 1,
  last_jump_line = nil,
}
function M.get_main_cursor_line(winid)
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return 1
  end

  local cursor = vim.api.nvim_win_get_cursor(winid)
  return cursor[1]
end
function M.jump_to_line(minimap_bufnr, minimap_winid, main_bufnr, main_winid)
  if not vim.api.nvim_win_is_valid(minimap_winid) or not vim.api.nvim_win_is_valid(main_winid) then
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(minimap_winid)
  local minimap_line = cursor[1]
  local minimap = require("xmap.minimap")
  local line_mapping = minimap.state.line_mapping
  local target_line = line_mapping[minimap_line] or minimap_line
  local main_line_count = vim.api.nvim_buf_line_count(main_bufnr)
  target_line = math.max(1, math.min(target_line, main_line_count))
  vim.api.nvim_win_set_cursor(main_winid, { target_line, 0 })
  local opts = config.get()
  if opts.navigation.auto_center then
    vim.api.nvim_win_call(main_winid, function()
      vim.cmd("normal! zz")
    end)
  end
  vim.api.nvim_set_current_win(main_winid)
  M.state.last_jump_line = target_line
end
function M.center_main_on_minimap_cursor(minimap_winid, main_bufnr, main_winid, line_mapping)
  if not (vim.api.nvim_win_is_valid(minimap_winid) and vim.api.nvim_win_is_valid(main_winid)) then
    return
  end
  if not vim.api.nvim_buf_is_valid(main_bufnr) then
    return
  end
  if vim.api.nvim_win_get_buf(main_winid) ~= main_bufnr then
    return
  end

  local minimap_line = vim.api.nvim_win_get_cursor(minimap_winid)[1]
  local target_line = minimap_line
  if type(line_mapping) == "table" and #line_mapping > 0 then
    target_line = line_mapping[minimap_line] or minimap_line
  end

  local max_line = vim.api.nvim_buf_line_count(main_bufnr)
  target_line = clamp(target_line, 1, max_line)

  pcall(vim.api.nvim_win_set_cursor, main_winid, { target_line, 0 })

  local opts = config.get()
  if opts.navigation.auto_center then
    vim.api.nvim_win_call(main_winid, function()
      vim.cmd("normal! zz")
    end)
  end
end
function M.update_minimap_cursor(minimap_winid, main_line, line_mapping)
  if not vim.api.nvim_win_is_valid(minimap_winid) then
    return
  end

  local minimap_line = main_line

  if type(line_mapping) == "table" and #line_mapping > 0 then
    -- ALGORITHM:
    -- - Pick the nearest rendered line at or before `main_line`.
    -- - Use binary search because `line_mapping` is sorted by source line.
    local lo, hi = 1, #line_mapping
    local best = 1

    while lo <= hi do
      local mid = math.floor((lo + hi) / 2)
      local source_line = line_mapping[mid]
      if source_line == main_line then
        best = mid
        break
      elseif source_line < main_line then
        best = mid
        lo = mid + 1
      else
        hi = mid - 1
      end
    end

    minimap_line = best
  end

  pcall(vim.api.nvim_win_set_cursor, minimap_winid, { minimap_line, 0 })
  M.state.minimap_cursor_line = minimap_line
end
function M.focus_minimap(minimap_winid)
  if not minimap_winid or not vim.api.nvim_win_is_valid(minimap_winid) then
    vim.notify("Minimap window not found", vim.log.levels.WARN)
    return
  end

  vim.api.nvim_set_current_win(minimap_winid)
end
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
function M.setup_minimap_keymaps(minimap_bufnr, minimap_winid, main_bufnr, main_winid)
  local opts = config.get()
  if opts.keymaps.jump then
    vim.keymap.set("n", opts.keymaps.jump, function()
      -- CONSTRAINTS:
      -- - Resolve the current target from minimap state.
      -- - Do not trust the window captured when keymaps were installed.
      local minimap = require("xmap.minimap")
      local current_main_bufnr = minimap.state.main_bufnr
      local current_main_winid = minimap.state.main_winid

      if not (current_main_bufnr and vim.api.nvim_buf_is_valid(current_main_bufnr)) then
        return
      end

      if not (current_main_winid and vim.api.nvim_win_is_valid(current_main_winid)) then
        current_main_winid = nil
      end

      if current_main_winid and vim.api.nvim_win_get_buf(current_main_winid) ~= current_main_bufnr then
        current_main_winid = nil
      end

      if not current_main_winid then
        for _, winid in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_buf(winid) == current_main_bufnr then
            current_main_winid = winid
            break
          end
        end
      end

      if not current_main_winid then
        return
      end

      M.jump_to_line(minimap_bufnr, minimap_winid, current_main_bufnr, current_main_winid)
    end, { buffer = minimap_bufnr, silent = true, desc = "Jump to line" })
  end
  if opts.keymaps.close then
    vim.keymap.set("n", opts.keymaps.close, function()
      require("xmap").close()
    end, { buffer = minimap_bufnr, silent = true, desc = "Close minimap" })
  end
end

return M
