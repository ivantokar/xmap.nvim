-- lua/xmap/lang/lua.lua
-- Lua language support for xmap.nvim
--
-- This provider implements Lua-specific logic required by the core minimap renderer:
--   - A set of default declaration keywords to show in the minimap (function/local function/...)
--   - A Tree-sitter query to obtain structural node ranges for highlighting
--   - A lightweight line-based parser (`parse_symbol`) that turns a source line into:
--       { keyword = "...", capture_type = "...", display = "..." }
--     where `capture_type` matches the generic icon/highlight maps in `treesitter.lua`.
--   - Comment detection and rendering (including TODO/FIXME style markers)

local M = {}

M.default_symbol_keywords = {
  "function",
  "local",
  "return",
}

M.default_highlight_keywords = vim.deepcopy(M.default_symbol_keywords)

local function ltrim(text)
  return (text:gsub("^%s+", ""))
end

local QUERY_VARIANTS = {
  -- Modern Lua parser
  [[
    (function_declaration) @function
    (local_function) @function
    (field) @variable
    (variable_declaration) @variable
  ]],

  -- Minimal fallback
  [[
    (function_declaration) @function
    (local_function) @function
  ]],
}

---Get Tree-sitter query candidates for Lua (newest-first).
---@return string[]
function M.get_queries()
  return QUERY_VARIANTS
end

---Get the primary Tree-sitter query string for Lua.
---@return string
function M.get_query()
  return QUERY_VARIANTS[1]
end

---Parse a Lua declaration line into a symbol item.
---@param line_text string
---@return {keyword:string, capture_type:string, display:string}|nil
function M.parse_symbol(line_text)
  local cleaned = ltrim(line_text or "")
  if cleaned == "" then
    return nil
  end

  -- return statements
  if cleaned == "return" or cleaned:match("^return%f[%W]") then
    local rest = vim.trim((cleaned:gsub("^return", "", 1)))
    local display = "return"
    if rest ~= "" then
      display = display .. " " .. rest
    end
    return { keyword = "return", capture_type = "function", display = display }
  end

  -- local function declarations: `local function foo(...)`
  do
    local name = cleaned:match("^local%s+function%s+([%w_%.]+)")
    if name then
      return { keyword = "function", capture_type = "function", display = "local function " .. name }
    end
  end

  -- global function declarations: `function foo(...)` or `function module.foo(...)`
  do
    local name = cleaned:match("^function%s+([%w_%.]+)")
    if name then
      return { keyword = "function", capture_type = "function", display = "function " .. name }
    end
  end

  -- local variable declarations: `local foo = ...` or `local foo, bar = ...`
  do
    local names = cleaned:match("^local%s+([%w_,%s]+)%s*=")
    if names then
      -- Extract first variable name
      local first_name = names:match("^([%w_]+)")
      if first_name then
        return { keyword = "local", capture_type = "variable", display = "local " .. first_name }
      end
    end
  end

  -- Module table assignments: `M.foo = function(...)` or `module.foo = function(...)`
  do
    local name = cleaned:match("^([%w_]+%.[%w_]+)%s*=%s*function%s*%(")
    if name then
      return { keyword = "function", capture_type = "function", display = "function " .. name }
    end
  end

  -- Table field function assignments: `foo = function(...)`
  do
    local name = cleaned:match("^([%w_]+)%s*=%s*function%s*%(")
    if name then
      return { keyword = "function", capture_type = "function", display = "function " .. name }
    end
  end

  return nil
end

---Check if a line is a comment line in Lua.
---@param trimmed string
---@return boolean
function M.is_comment_line(trimmed)
  -- Lua supports:
  --   - line comments: --
  --   - block comments: --[[ ... ]]
  --   - block comment continuation lines starting with --
  return trimmed:match("^%-%-") ~= nil
end

---Detect file header comments to reduce noise.
---@param lines string[]
---@param line_nr integer 1-indexed
---@return boolean
function M.is_file_header(lines, line_nr)
  -- File header blocks (license banners, generated comments) can dominate the minimap.
  -- We detect "a run of >=3 comment lines at the top of the file" and suppress them.
  if line_nr > 50 then
    return false
  end

  local header_end = 0
  local comment_count = 0

  for i = 1, math.min(50, #lines) do
    local trimmed = vim.trim(lines[i])

    if trimmed == "" then
      header_end = i
      goto continue
    end

    if not M.is_comment_line(trimmed) then
      break
    end

    comment_count = comment_count + 1
    header_end = i

    ::continue::
  end

  return comment_count >= 3 and line_nr <= header_end
end

---Extract comment text (remove markers, get first line only).
---@param line string
---@return string|nil, string|nil, boolean, string|nil
function M.extract_comment(line)
  -- Extract a compact comment text suitable for minimap display:
  --   - remove comment markers (--, --[[, ]])
  --   - detect marker prefixes like TODO:/FIXME:/NOTE:
  --   - truncate to keep minimap lines compact
  local trimmed = vim.trim(line)

  local is_doc_comment = trimmed:match("^%-%-%-") ~= nil

  local text = trimmed
    :gsub("^%-%-%-+%s*", "")
    :gsub("^%-%-+%s*", "")
    :gsub("^%-%-%[%[%s*", "")
    :gsub("%]%]%s*$", "")

  if text == "" then
    return nil, nil, is_doc_comment
  end

  local marker = nil
  if text:match("^TODO:") then
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
  elseif text:match("^HACK:") then
    marker = "HACK"
    text = text:gsub("^HACK:%s*", "")
  end

  local raw_text = text

  if #text > 35 then
    text = text:sub(1, 32) .. "..."
  end

  return text, marker, is_doc_comment, raw_text
end

---Render a comment entry for the minimap (no comment prefix).
---@param line string
---@param line_nr integer 1-indexed
---@param all_lines string[]
---@return {kind:"marker"|"comment", marker:string|nil, text:string}|nil
function M.render_comment(line, line_nr, all_lines)
  -- Convert a source comment line into a minimap entry.
  -- Returns:
  --   - { kind="marker", marker="TODO", text="..." } for marker comments
  --   - { kind="comment", text="..." } for regular comments (non-header)
  local text, marker = M.extract_comment(line)
  if marker then
    return { kind = "marker", marker = marker, text = text or "" }
  end

  if text and not M.is_file_header(all_lines, line_nr) then
    return { kind = "comment", marker = nil, text = text }
  end

  return nil
end

return M
