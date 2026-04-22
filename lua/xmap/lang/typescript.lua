-- PURPOSE:
-- - Parse TypeScript/TSX declarations and comment forms for minimap rendering.
-- CONSTRAINTS:
-- - Treat JSX block comments as comment lines.

local M = {}

M.default_symbol_keywords = {
  "function",
  "method",
  "class",
  "interface",
  "type",
  "enum",
  "namespace",
  "module",
  "return",
}

M.default_highlight_keywords = vim.deepcopy(M.default_symbol_keywords)

local function ltrim(text)
  return (text:gsub("^%s+", ""))
end

local RESERVED = {
  ["if"] = true,
  ["for"] = true,
  ["while"] = true,
  ["switch"] = true,
  ["catch"] = true,
  ["return"] = true,
  ["throw"] = true,
  ["break"] = true,
  ["continue"] = true,
  ["case"] = true,
  ["default"] = true,
  ["try"] = true,
  ["do"] = true,
  ["else"] = true,
  ["new"] = true,
  ["delete"] = true,
  ["typeof"] = true,
  ["instanceof"] = true,
  ["void"] = true,
  ["yield"] = true,
  ["await"] = true,
  ["import"] = true,
  ["export"] = true,
  ["from"] = true,
  ["as"] = true,
  ["in"] = true,
  ["of"] = true,
}

local function strip_ts_modifiers(text)
  -- PURPOSE:
  -- - Remove declaration modifiers before pattern matching.
  local out = ltrim(text)

  local function strip(pattern)
    local next_out, count = out:gsub(pattern, "", 1)
    if count > 0 then
      out = ltrim(next_out)
      return true
    end
    return false
  end

  while true do
    local changed = false
    changed = strip("^(export)%s+") or changed
    changed = strip("^(default)%s+") or changed
    changed = strip("^(declare)%s+") or changed
    changed = strip("^(abstract)%s+") or changed
    changed = strip("^(public)%s+") or changed
    changed = strip("^(private)%s+") or changed
    changed = strip("^(protected)%s+") or changed
    changed = strip("^(readonly)%s+") or changed
    changed = strip("^(static)%s+") or changed
    changed = strip("^(override)%s+") or changed
    changed = strip("^(async)%s+") or changed

    if not changed then
      break
    end
  end

  return out
end

local function looks_like_arrow_function(rhs)
  -- PURPOSE:
  -- - Distinguish function-valued assignments from plain variables.
  local text = ltrim(rhs or "")
  text = text:gsub("^async%s+", "")

  if text:match("^function") then
    return true
  end
  if text:match("^%b()%s*=>") then
    return true
  end
  if text:match("^[%w_$]+%s*=>") then
    return true
  end
  if text:match("^<[^>]+>%s*%b()%s*=>") then
    return true
  end
  if text:match("^<[^>]+>%s*[%w_$]+%s*=>") then
    return true
  end

  return false
end

local QUERY_VARIANTS = {
  -- CONSTRAINTS:
  -- - Keep a minimal fallback for parser/query compatibility.
  [[
    (class_declaration) @class
    (interface_declaration) @class
    (type_alias_declaration) @class
    (enum_declaration) @class

    (function_declaration) @function
    (method_definition) @method
  ]],
  [[
    (class_declaration) @class
    (function_declaration) @function
  ]],
}
function M.get_queries()
  return QUERY_VARIANTS
end
function M.get_query()
  return QUERY_VARIANTS[1]
end
function M.parse_symbol(line_text)
  local cleaned = strip_ts_modifiers(line_text or "")
  if cleaned == "" then
    return nil
  end
  if cleaned:match("^@") then
    return nil
  end
  if cleaned == "return" or cleaned:match("^return%f[%W]") then
    local rest = vim.trim((cleaned:gsub("^return", "", 1)))
    rest = vim.trim((rest:gsub(";+%s*$", "")))
    local display = "return"
    if rest ~= "" then
      display = display .. " " .. rest
    end
    return { keyword = "return", capture_type = "function", display = display }
  end
  do
    local name = cleaned:match("^class%s+([%w_$]+)")
    if name then
      return { keyword = "class", capture_type = "class", display = "class " .. name }
    end
  end

  do
    local name = cleaned:match("^interface%s+([%w_$]+)")
    if name then
      return { keyword = "interface", capture_type = "class", display = "interface " .. name }
    end
  end

  do
    local name = cleaned:match("^type%s+([%w_$]+)")
    if name then
      return { keyword = "type", capture_type = "class", display = "type " .. name }
    end
  end

  do
    local name = cleaned:match("^const%s+enum%s+([%w_$]+)") or cleaned:match("^enum%s+([%w_$]+)")
    if name then
      return { keyword = "enum", capture_type = "class", display = "enum " .. name }
    end
  end

  do
    local keyword, name = cleaned:match("^(namespace)%s+([%w_$.]+)") or cleaned:match("^(module)%s+([%w_$.]+)")
    if keyword and name then
      return { keyword = keyword, capture_type = "class", display = keyword .. " " .. name }
    end
  end
  do
    local name = cleaned:match("^function%s*%*?%s+([%w_$]+)")
    if name then
      return { keyword = "function", capture_type = "function", display = "function " .. name }
    end
  end
  do
    local kw, name = cleaned:match("^(%a+)%s+([%w_$]+)")
    if (kw == "const" or kw == "let" or kw == "var") and name then
      local rest = cleaned:match("^" .. kw .. "%s+" .. name .. "%s*(.*)$") or ""
      local eq = rest:find("=", 1, true)
      if eq then
        local rhs = rest:sub(eq + 1)
        if looks_like_arrow_function(rhs) then
          return { keyword = "function", capture_type = "function", display = "function " .. name }
        end
      end
      return { keyword = kw, capture_type = "variable", display = kw .. " " .. name }
    end
  end
  do
    local member = strip_ts_modifiers(cleaned)
    member = member:gsub("^%*%s*", "")

    local accessor, acc_name = member:match("^(get)%s+([%w_$]+)%s*<[^>]*>%s*%b()%s*[:{]")
    if not accessor then
      accessor, acc_name = member:match("^(set)%s+([%w_$]+)%s*<[^>]*>%s*%b()%s*[:{]")
    end
    if not accessor then
      accessor, acc_name = member:match("^(get)%s+([%w_$]+)%s*%b()%s*[:{]")
    end
    if not accessor then
      accessor, acc_name = member:match("^(set)%s+([%w_$]+)%s*%b()%s*[:{]")
    end
    if accessor and acc_name then
      if not RESERVED[acc_name] then
        return {
          keyword = "method",
          capture_type = "method",
          display = "method " .. accessor .. " " .. acc_name,
        }
      end
    end

    local meth_name = member:match("^([%w_$]+)%s*[%?!]*%s*<[^>]*>%s*%b()%s*[:{]")
      or member:match("^([%w_$]+)%s*[%?!]*%s*%b()%s*[:{]")
    if meth_name and not RESERVED[meth_name] then
      return { keyword = "method", capture_type = "method", display = "method " .. meth_name }
    end
  end
  do
    local member = strip_ts_modifiers(cleaned)
    local name, rhs = member:match("^([%w_$]+)%s*=%s*(.+)$")
    if not name then
      name, rhs = member:match("^([%w_$]+)%s*[%?!%!]*%s*:%s*.-=%s*(.+)$")
    end
    if name and rhs and not RESERVED[name] and looks_like_arrow_function(rhs) then
      return { keyword = "method", capture_type = "method", display = "method " .. name }
    end
  end
  do
    local member = strip_ts_modifiers(cleaned)
    local name = member:match("^([%w_$]+)%s*[%?!%!]*%s*:%s+")
    if name and not RESERVED[name] then
      return { keyword = "property", capture_type = "variable", display = "property " .. name }
    end
  end

  return nil
end
function M.is_comment_line(trimmed)
  -- PURPOSE:
  -- - Detect TS, block, continuation, and JSX comment lines.
  return trimmed:match("^//")
    or trimmed:match("^/%*")
    or trimmed:match("^%*/")
    or trimmed:match("^%*%s")
    or trimmed == "*"
    or trimmed:match("^%{%s*/%*")
end
function M.is_file_header(lines, line_nr)
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

local function is_block_comment_start(trimmed)
  return trimmed:match("^/%*") ~= nil
end

local function is_block_comment_end(trimmed)
  return trimmed:match("^%*/") ~= nil
end

local function is_jsx_block_comment_line(trimmed)
  return trimmed:match("^%{%s*/%*") ~= nil
end

local function find_enclosing_block_comment_start(all_lines, line_nr)
  for i = line_nr - 1, math.max(1, line_nr - 200), -1 do
    local trimmed = vim.trim(all_lines[i] or "")
    if is_block_comment_end(trimmed) then
      return nil
    end
    if is_block_comment_start(trimmed) then
      return i
    end
  end
  return nil
end

local function find_first_block_comment_entry(all_lines, start_line_nr)
  -- ALGORITHM:
  -- - Prefer the first non-tag text line inside the block.
  -- - Fall back to the first marker line when the block is marker-only.
  local marker_line_nr, marker_name, marker_text = nil, nil, nil
  do
    local text, marker = M.extract_comment(all_lines[start_line_nr] or "")
    if marker then
      marker_line_nr, marker_name, marker_text = start_line_nr, marker, text or ""
    elseif text and text ~= "" and not text:match("^@[%w_]+") then
      return start_line_nr, "comment", nil, text
    end
  end

  for i = start_line_nr + 1, math.min(#all_lines, start_line_nr + 200) do
    local trimmed = vim.trim(all_lines[i] or "")
    if is_block_comment_end(trimmed) then
      break
    end

    local text, marker = M.extract_comment(all_lines[i] or "")
    if marker and not marker_line_nr then
      marker_line_nr, marker_name, marker_text = i, marker, text or ""
    end

    if text and text ~= "" and not text:match("^@[%w_]+") then
      return i, "comment", nil, text
    end
  end

  if marker_line_nr then
    return marker_line_nr, "marker", marker_name, marker_text or ""
  end

  return nil
end
function M.extract_comment(line)
  local trimmed = vim.trim(line)

  local is_doc_comment = trimmed:match("^///") or trimmed:match("^/%*%*") or trimmed:match("^%{%s*/%*%*")
  if trimmed == "/*" or trimmed == "/**" or trimmed == "*/" or trimmed:match("^%*/%s*%}$") then
    return nil, nil, is_doc_comment
  end
  do
    local jsx_inner = trimmed:match("^%{%s*/%*(.-)%*/%s*%}$")
    if jsx_inner ~= nil then
      local text = vim.trim((jsx_inner:gsub("^%*+%s*", "")))
      if text == "" then
        return nil, nil, is_doc_comment
      end

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

      local raw_text = text

      if #text > 35 then
        text = text:sub(1, 32) .. "..."
      end

      return text, marker, is_doc_comment, raw_text
    end
  end

  local text = trimmed
    :gsub("^///%s*", "")
    :gsub("^//%s*", "")
    :gsub("^/%*%*%s*", "")
    :gsub("^/%*%s*", "")
    :gsub("^%*%s*", "")
    :gsub("%s*%*/$", "")

  if text == "" then
    return nil, nil, is_doc_comment
  end

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

  local raw_text = text

  if #text > 35 then
    text = text:sub(1, 32) .. "..."
  end

  return text, marker, is_doc_comment, raw_text
end
function M.render_comment(line, line_nr, all_lines)
  -- PURPOSE:
  -- - Collapse block comments to one rendered entry and skip closing lines.
  local trimmed = vim.trim(line)
  if is_jsx_block_comment_line(trimmed) then
    local text, marker = M.extract_comment(line)
    if marker then
      return { kind = "marker", marker = marker, text = text or "" }
    end
    if text and not M.is_file_header(all_lines, line_nr) then
      return { kind = "comment", marker = nil, text = text }
    end
    return nil
  end
  if is_block_comment_end(trimmed) then
    return nil
  end
  if is_block_comment_start(trimmed) then
    local text, marker = M.extract_comment(line)
    if marker then
      return { kind = "marker", marker = marker, text = text or "" }
    end
    if text and not text:match("^@[%w_]+") and not M.is_file_header(all_lines, line_nr) then
      return { kind = "comment", marker = nil, text = text }
    end
    return nil
  end
  if trimmed:match("^%*") then
    local start_line_nr = find_enclosing_block_comment_start(all_lines, line_nr)
    if not start_line_nr then
      return nil
    end

    local best_line_nr, kind, marker, text = find_first_block_comment_entry(all_lines, start_line_nr)
    if best_line_nr ~= line_nr or not kind then
      return nil
    end

    if kind == "marker" then
      return { kind = "marker", marker = marker, text = text or "" }
    end

    if text and not M.is_file_header(all_lines, line_nr) then
      return { kind = "comment", marker = nil, text = text }
    end

    return nil
  end

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
