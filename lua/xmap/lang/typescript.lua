-- lua/xmap/lang/typescript.lua
-- TypeScript language support for xmap.nvim
--
-- This provider implements a lightweight, line-based parser for common TypeScript
-- declarations (functions/classes/types/etc.) and a Tree-sitter query for structural
-- scope highlighting.

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
  "const",
  "let",
  "var",
  "property",
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
  -- Strip common modifiers so we can match declarations consistently.
  -- Examples:
  --   export default class Foo
  --   public async render(): JSX.Element {
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
  local text = ltrim(rhs or "")
  text = text:gsub("^async%s+", "")

  if text:match("^function") then
    return true
  end

  -- Arrow functions:
  --   (a, b) => ...
  --   a => ...
  --   <T>(a: T) => ...
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
  -- TypeScript / TSX
  [[
    (class_declaration) @class
    (interface_declaration) @class
    (type_alias_declaration) @class
    (enum_declaration) @class

    (function_declaration) @function
    (method_definition) @method
  ]],

  -- Minimal fallback
  [[
    (class_declaration) @class
    (function_declaration) @function
  ]],
}

---Get Tree-sitter query candidates for TypeScript (newest-first).
---@return string[]
function M.get_queries()
  return QUERY_VARIANTS
end

---Get the primary Tree-sitter query string for TypeScript.
---@return string
function M.get_query()
  return QUERY_VARIANTS[1]
end

---Parse a TypeScript declaration line into a symbol item.
---@param line_text string
---@return {keyword:string, capture_type:string, display:string}|nil
function M.parse_symbol(line_text)
  local cleaned = strip_ts_modifiers(line_text or "")
  if cleaned == "" then
    return nil
  end

  -- Ignore decorator lines (Angular/TS ecosystems)
  if cleaned:match("^@") then
    return nil
  end

  -- class / interface / type / enum / namespace / module
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

  -- function declarations
  do
    local name = cleaned:match("^function%s*%*?%s+([%w_$]+)")
    if name then
      return { keyword = "function", capture_type = "function", display = "function " .. name }
    end
  end

  -- const/let/var declarations (treat arrow/function assignments as "function")
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

  -- Member methods: `foo() {` / `foo(): T {` / `get foo() {`
  do
    local member = strip_ts_modifiers(cleaned)
    member = member:gsub("^%*%s*", "") -- generator marker

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

  -- Member arrow/function properties: `foo = (...) =>` / `foo: T = (...) =>`
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

  -- Property signatures (interfaces/types/classes): `foo?: T` / `foo!: T`
  do
    local member = strip_ts_modifiers(cleaned)
    local name = member:match("^([%w_$]+)%s*[%?!%!]*%s*:%s+")
    if name and not RESERVED[name] then
      return { keyword = "property", capture_type = "variable", display = "property " .. name }
    end
  end

  return nil
end

---Check if a line is a comment line in TypeScript.
---@param trimmed string
---@return boolean
function M.is_comment_line(trimmed)
  -- TS/TSX supports `//` line comments and `/* ... */` block comments.
  -- In TSX (typescriptreact), JSX comments look like: `{/* comment */}`.
  --
  -- Note: avoid treating generator methods (`*foo() {}`) as comments by requiring
  -- whitespace after `*` for block-comment continuation lines.
  return trimmed:match("^//")
    or trimmed:match("^/%*")
    or trimmed:match("^%*/")
    or trimmed:match("^%*%s")
    or trimmed == "*"
    or trimmed:match("^%{%s*/%*")
end

---Detect file header comments to reduce noise.
---@param lines string[]
---@param line_nr integer 1-indexed
---@return boolean
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
  -- Walk backwards and find the nearest `/*` start without crossing a `*/` end.
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
  -- Return the first meaningful comment entry within a /* ... */ block:
  --   - first non-@tag text line (preferred)
  --   - otherwise the first MARK/TODO/etc marker line
  -- The returned `line_nr` is where the entry should be rendered.
  local marker_line_nr, marker_name, marker_text = nil, nil, nil

  -- Opening line can carry text: `/** Summary` or `/* Summary */`
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

---Extract comment text (remove markers, get first line only).
---@param line string
---@return string|nil, string|nil, boolean
function M.extract_comment(line)
  local trimmed = vim.trim(line)

  local is_doc_comment = trimmed:match("^///") or trimmed:match("^/%*%*") or trimmed:match("^%{%s*/%*%*")

  -- Skip pure opening/closing markers for block/JSX comments.
  if trimmed == "/*" or trimmed == "/**" or trimmed == "*/" or trimmed:match("^%*/%s*%}$") then
    return nil, nil, is_doc_comment
  end

  -- JSX comment: `{/* ... */}` (TSX)
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

      if #text > 35 then
        text = text:sub(1, 32) .. "..."
      end

      return text, marker, is_doc_comment
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

  if #text > 35 then
    text = text:sub(1, 32) .. "..."
  end

  return text, marker, is_doc_comment
end

---Render a comment entry for the minimap (no comment prefix).
---@param line string
---@param line_nr integer 1-indexed
---@param all_lines string[]
---@return {kind:"marker"|"comment", marker:string|nil, text:string}|nil
function M.render_comment(line, line_nr, all_lines)
  local trimmed = vim.trim(line)
  -- TSX JSX comment: `{/* ... */}`.
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

  -- Never render the closing line of a block comment.
  if is_block_comment_end(trimmed) then
    return nil
  end

  -- Block comment opening line: render only if it contains meaningful text.
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

  -- Block comment continuation (`* ...`): render only the first meaningful text line.
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
