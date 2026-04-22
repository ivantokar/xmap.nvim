-- PURPOSE:
-- - Parse Swift declarations/comments with parser-version-safe query fallbacks.

local M = {}

M.default_symbol_keywords = {
  "func",
  "init",
  "deinit",
  "class",
  "struct",
  "enum",
  "protocol",
  "extension",
  "typealias",
  "actor",
  "subscript",
  "return",
}

M.default_highlight_keywords = {
  "func",
  "init",
  "deinit",
  "class",
  "struct",
  "enum",
  "protocol",
  "extension",
  "typealias",
  "actor",
  "subscript",
  "return",
}

local function ltrim(text)
  return (text:gsub("^%s+", ""))
end

local function strip_swift_attributes(text)
  -- PURPOSE:
  -- - Ignore leading Swift attributes before keyword detection.
  local out = ltrim(text)

  while true do
    local before = out
    out = out:gsub("^@[%w_]+%b()%s*", "")
    out = out:gsub("^@[%w_]+%s*", "")

    out = ltrim(out)
    if out == before then
      break
    end
  end

  return out
end

local function strip_swift_modifiers(text)
  -- PURPOSE:
  -- - Remove declaration modifiers that obscure the primary symbol keyword.
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
    changed = strip("^(public|private|fileprivate|internal|open)%s*%b()%s*") or changed
    changed = strip("^(public|private|fileprivate|internal|open)%s+") or changed
    changed = strip("^final%s+") or changed
    changed = strip("^static%s+") or changed
    changed = strip("^indirect%s+") or changed
    changed = strip("^lazy%s+") or changed
    changed = strip("^weak%s+") or changed
    changed = strip("^unowned%s+") or changed
    changed = strip("^override%s+") or changed
    changed = strip("^mutating%s+") or changed
    changed = strip("^nonmutating%s+") or changed
    changed = strip("^convenience%s+") or changed
    changed = strip("^required%s+") or changed
    changed = strip("^dynamic%s+") or changed
    if out:match("^class%s+(func|var|let|subscript)%s") then
      changed = strip("^class%s+") or changed
    end

    if not changed then
      break
    end
  end

  return out
end

local function capture_token_after(keyword, text, token_pattern)
  return text:match("^" .. keyword .. "%s+(" .. token_pattern .. ")")
end

local function capture_func_name(text)
  return capture_token_after("func", text, "[^%s%(<]+")
end

local function capture_type_name_after(keyword, text)
  return capture_token_after(keyword, text, "[^%s%(<:{=]+")
end

local function capture_value_name_after(keyword, text)
  return capture_token_after(keyword, text, "[^%s%(<:{=]+")
end

local QUERY_VARIANTS = {
  -- CONSTRAINTS:
  -- - Keep fallback order aligned with known Swift parser node drift.
  [[
    (class_declaration) @class
    (struct_declaration) @class
    (enum_declaration) @class
    (protocol_declaration) @class
    (extension_declaration) @class
    (typealias_declaration) @class
    (actor_declaration) @class

    (function_declaration) @function
    (init_declaration) @function
    (deinitializer_declaration) @function
    (subscript_declaration) @function

    (property_declaration) @variable
  ]],
  [[
    (class_declaration) @class
    (struct_declaration) @class
    (enum_declaration) @class
    (protocol_declaration) @class
    (extension_declaration) @class
    (typealias_declaration) @class
    (actor_declaration) @class

    (function_declaration) @function
    (init_declaration) @function
    (deinit_declaration) @function
    (subscript_declaration) @function

    (property_declaration) @variable
  ]],
  [[
    (class_declaration) @class
    (struct_declaration) @class
    (enum_declaration) @class
    (protocol_declaration) @class
    (extension_declaration) @class

    (function_declaration) @function
    (init_declaration) @function

    (property_declaration) @variable
  ]],
  [[
    (class_declaration) @class
    (function_declaration) @function
    (init_declaration) @function
    (property_declaration) @variable
  ]],
  [[
    (class_declaration) @class
    (function_declaration) @function
    (init_declaration) @function
  ]],
}
function M.get_queries()
  return QUERY_VARIANTS
end
function M.get_query()
  return QUERY_VARIANTS[1]
end
function M.parse_symbol(line_text)
  local cleaned = strip_swift_modifiers(strip_swift_attributes(line_text))
  if cleaned == "" then
    return nil
  end
  local init_kind = cleaned:match("^init([?!]?)%s*%(")
  if init_kind ~= nil then
    local keyword = "init"
    local display = init_kind ~= "" and ("init" .. init_kind) or "init"
    return { keyword = keyword, capture_type = "function", display = display }
  end

  if cleaned:match("^deinit%s*[{%s]") then
    return { keyword = "deinit", capture_type = "function", display = "deinit" }
  end
  local func_name = capture_func_name(cleaned)
  if func_name then
    return { keyword = "func", capture_type = "function", display = "func " .. func_name }
  end
  local type_keywords = { "class", "struct", "enum", "protocol", "extension", "typealias", "actor" }
  for _, keyword in ipairs(type_keywords) do
    local name = capture_type_name_after(keyword, cleaned)
    if name then
      return { keyword = keyword, capture_type = "class", display = keyword .. " " .. name }
    end
  end
  local let_name = capture_value_name_after("let", cleaned)
  if let_name then
    return { keyword = "let", capture_type = "variable", display = "let " .. let_name }
  end

  local var_name = capture_value_name_after("var", cleaned)
  if var_name then
    return { keyword = "var", capture_type = "variable", display = "var " .. var_name }
  end

  if cleaned:match("^subscript%s*%(") then
    return { keyword = "subscript", capture_type = "function", display = "subscript" }
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

  return nil
end
function M.is_comment_line(trimmed)
  return trimmed:match("^//") or trimmed:match("^/%*") or trimmed:match("^%*")
end
function M.is_file_header(lines, line_nr)
  -- PURPOSE:
  -- - Suppress large header comment blocks near file start.
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

  local is_doc_comment = trimmed:match("^///") or trimmed:match("^/%*%*")

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
  -- - Render marker comments and regular comments outside file headers.
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
