-- PURPOSE:
-- - Parse Lua symbols/comments for minimap rendering and Tree-sitter fallbacks.

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
  -- CONSTRAINTS:
  -- - Order queries from richest to most compatible.
  [[
    (function_declaration) @function
    (local_function) @function
    (field) @variable
    (variable_declaration) @variable
  ]],
  [[
    (function_declaration) @function
    (local_function) @function
  ]],
}
function M.get_queries()
  return QUERY_VARIANTS
end
function M.get_query()
  return QUERY_VARIANTS[1]
end
function M.parse_symbol(line_text)
  local cleaned = ltrim(line_text or "")
  if cleaned == "" then
    return nil
  end
  if cleaned == "return" or cleaned:match("^return%f[%W]") then
    local rest = vim.trim((cleaned:gsub("^return", "", 1)))
    local display = "return"
    if rest ~= "" then
      display = display .. " " .. rest
    end
    return { keyword = "return", capture_type = "function", display = display }
  end
  do
    local name = cleaned:match("^local%s+function%s+([%w_%.]+)")
    if name then
      return { keyword = "function", capture_type = "function", display = "local function " .. name }
    end
  end
  do
    local name = cleaned:match("^function%s+([%w_%.]+)")
    if name then
      return { keyword = "function", capture_type = "function", display = "function " .. name }
    end
  end
  do
    local names = cleaned:match("^local%s+([%w_,%s]+)%s*=")
    if names then
      local first_name = names:match("^([%w_]+)")
      if first_name then
        return { keyword = "local", capture_type = "variable", display = "local " .. first_name }
      end
    end
  end
  do
    local name = cleaned:match("^([%w_]+%.[%w_]+)%s*=%s*function%s*%(")
    if name then
      return { keyword = "function", capture_type = "function", display = "function " .. name }
    end
  end
  do
    local name = cleaned:match("^([%w_]+)%s*=%s*function%s*%(")
    if name then
      return { keyword = "function", capture_type = "function", display = "function " .. name }
    end
  end

  return nil
end
function M.is_comment_line(trimmed)
  return trimmed:match("^%-%-") ~= nil
end
function M.is_file_header(lines, line_nr)
  -- PURPOSE:
  -- - Suppress banner-style comment blocks near the top of a file.
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
function M.extract_comment(line)
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
function M.render_comment(line, line_nr, all_lines)
  -- PURPOSE:
  -- - Render marker comments and non-header comments only.
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
