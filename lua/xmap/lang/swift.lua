-- lua/xmap/lang/swift.lua
-- Swift language support for xmap.nvim
--
-- This provider implements Swift-specific logic required by the core minimap renderer:
--   - A set of default declaration keywords to show in the minimap (func/struct/enum/...)
--   - A Tree-sitter query (with fallbacks) to obtain structural node ranges for highlighting
--   - A lightweight line-based parser (`parse_symbol`) that turns a source line into:
--       { keyword = "...", capture_type = "...", display = "..." }
--     where `capture_type` matches the generic icon/highlight maps in `treesitter.lua`.
--   - Comment detection and rendering (including MARK/TODO/FIXME style markers)
--
-- Why both Tree-sitter *and* a line parser?
--   - Tree-sitter is optional and may not be installed.
--   - Even when available, we only need it for structural highlighting ranges.
--   - For the minimap list itself, a cheap line-based parser is often enough and avoids
--     tight coupling to Tree-sitter node names across parser versions.

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
  "let",
  "var",
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
  "let",
  "var",
  "subscript",
  "return",
}

local function ltrim(text)
  return (text:gsub("^%s+", ""))
end

local function strip_swift_attributes(text)
  -- Swift declarations often start with attributes like:
  --   @MainActor
  --   @available(iOS 17, *)
  -- For minimap display we remove leading attributes to find the actual keyword.
  local out = ltrim(text)

  while true do
    local before = out

    -- Attributes with args: @available(...)
    out = out:gsub("^@[%w_]+%b()%s*", "")
    -- Attributes without args: @MainActor
    out = out:gsub("^@[%w_]+%s*", "")

    out = ltrim(out)
    if out == before then
      break
    end
  end

  return out
end

local function strip_swift_modifiers(text)
  -- Swift declarations also often contain modifiers:
  --   public/private/internal/open, final, static, override, ...
  -- We strip common ones so `parse_symbol` can match on `func`, `struct`, etc.
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

    -- Access control (incl. private(set))
    changed = strip("^(public|private|fileprivate|internal|open)%s*%b()%s*") or changed
    changed = strip("^(public|private|fileprivate|internal|open)%s+") or changed

    -- Common modifiers
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

    -- `class` can be a modifier for members (class func / class var), but also a type declaration.
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
  -- Tree-sitter node names for Swift have changed across parser versions.
  -- To avoid a hard failure on first run, we provide query candidates ordered
  -- from "newest known" to "most compatible". `treesitter.lua` tries these in
  -- order and caches the first one that parses successfully.

  -- Newer parsers
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

  -- Some parsers use `deinit_declaration`
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

  -- Without newer declarations (max compatibility)
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

  -- Minimal (original)
  [[
    (class_declaration) @class
    (function_declaration) @function
    (init_declaration) @function
    (property_declaration) @variable
  ]],

  -- Minimal without properties (fallback)
  [[
    (class_declaration) @class
    (function_declaration) @function
    (init_declaration) @function
  ]],
}

---Get Tree-sitter query candidates for Swift (newest-first).
---@return string[]
function M.get_queries()
  return QUERY_VARIANTS
end

---Get the primary Tree-sitter query string for Swift.
---@return string
function M.get_query()
  return QUERY_VARIANTS[1]
end

---Parse a Swift declaration line into a symbol item.
---@param line_text string
---@return {keyword:string, capture_type:string, display:string}|nil
function M.parse_symbol(line_text)
  -- Parsing strategy:
  --   1) trim + strip attributes/modifiers
  --   2) detect declaration keyword
  --   3) capture a human-friendly name (when possible)
  --   4) map to a generic capture_type used by `treesitter.get_icon_for_type`
  local cleaned = strip_swift_modifiers(strip_swift_attributes(line_text))
  if cleaned == "" then
    return nil
  end

  -- init/deinit (support init?, init!)
  local init_kind = cleaned:match("^init([?!]?)%s*%(")
  if init_kind ~= nil then
    local keyword = "init"
    local display = init_kind ~= "" and ("init" .. init_kind) or "init"
    return { keyword = keyword, capture_type = "function", display = display }
  end

  if cleaned:match("^deinit%s*[{%s]") then
    return { keyword = "deinit", capture_type = "function", display = "deinit" }
  end

  -- func
  local func_name = capture_func_name(cleaned)
  if func_name then
    return { keyword = "func", capture_type = "function", display = "func " .. func_name }
  end

  -- types
  local type_keywords = { "class", "struct", "enum", "protocol", "extension", "typealias", "actor" }
  for _, keyword in ipairs(type_keywords) do
    local name = capture_type_name_after(keyword, cleaned)
    if name then
      return { keyword = keyword, capture_type = "class", display = keyword .. " " .. name }
    end
  end

  -- properties
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

  -- return statements (useful for quickly spotting exits/JSX returns)
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

---Check if a line is a comment line in Swift.
---@param trimmed string
---@return boolean
function M.is_comment_line(trimmed)
  -- Swift supports:
  --   - line comments: //
  --   - doc comments:  ///
  --   - block comments: /* ... */
  -- plus block-comment "continuation" lines that often start with `*`.
  return trimmed:match("^//") or trimmed:match("^/%*") or trimmed:match("^%*")
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
---@return string|nil, string|nil, boolean
function M.extract_comment(line)
  -- Extract a compact comment text suitable for minimap display:
  --   - remove comment markers (//, ///, /*, *)
  --   - detect marker prefixes like MARK:/TODO:/FIXME:
  --   - truncate to keep minimap lines compact
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
