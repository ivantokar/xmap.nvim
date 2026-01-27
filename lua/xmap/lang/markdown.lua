-- lua/xmap/lang/markdown.lua
-- Markdown language support for xmap.nvim
--
-- Provides a minimal heading parser to build a TOC-style minimap for Markdown:
--   - ATX headings: #, ##, ...
--   - Setext headings: title line + === / --- underline (rendered on the first line)
--   - Fenced code block starts (``` / ~~~)
--   - Images: ![alt](path)

local M = {}

M.default_symbol_keywords = { "H1", "H2", "H3", "H4", "H5", "H6", "code", "image", "link", "html" }
M.default_highlight_keywords = vim.deepcopy(M.default_symbol_keywords)

local HEADING_ICONS = {
  [1] = "󰉫",
  [2] = "󰉬",
  [3] = "󰉭",
  [4] = "󰉮",
  [5] = "󰉯",
  [6] = "󰉰",
}

local IMAGE_ICON = "󰋩"
local LINK_ICON = "󰌷"
local HTML_ICON = ""

local fence_cache = setmetatable({}, { __mode = "k" })

local QUERY_VARIANTS = {
  [[
    (atx_heading) @class
    (setext_heading) @class
  ]],
  [[
    (atx_heading) @class
  ]],
  [[
    (setext_heading) @class
  ]],
  [[
    (heading) @class
  ]],
  [[
    (section) @class
  ]],
}

---Get Tree-sitter query candidates for Markdown headings.
---@return string[]
function M.get_queries()
  return QUERY_VARIANTS
end

---Get the primary Tree-sitter query string for Markdown.
---@return string
function M.get_query()
  return QUERY_VARIANTS[1]
end

local function strip_blockquote_prefix(text)
  return (text:gsub("^>+%s*", ""))
end

local function normalize_text(text)
  text = vim.trim(text or "")
  if text == "" then
    return ""
  end
  return (text:gsub("%s+", " "))
end

local function parse_fence_marker(text)
  local cleaned = strip_blockquote_prefix(text or "")
  local ticks, rest = cleaned:match("^(```+)%s*(.*)$")
  if ticks then
    return "`", #ticks, rest
  end
  local tildes, tilde_rest = cleaned:match("^(~~~+)%s*(.*)$")
  if tildes then
    return "~", #tildes, tilde_rest
  end
  return nil
end

local function get_fence_info(all_lines)
  if type(all_lines) ~= "table" then
    return nil
  end

  local cached = fence_cache[all_lines]
  if cached then
    return cached
  end

  local info = { inside = {}, fence = {} }
  local stack = {}

  for i, line in ipairs(all_lines) do
    local trimmed = vim.trim(line or "")
    local marker_char, marker_len, rest = parse_fence_marker(trimmed)
    if marker_char then
      local top = stack[#stack]
      if top and top.char == marker_char and marker_len >= top.len then
        stack[#stack] = nil
        info.fence[i] = { opening = false, info = normalize_text(rest) }
      else
        table.insert(stack, { char = marker_char, len = marker_len })
        info.fence[i] = { opening = true, info = normalize_text(rest) }
      end
    end
    info.inside[i] = #stack > 0
  end

  fence_cache[all_lines] = info
  return info
end

local function heading_symbol(level, text)
  local keyword = "H" .. tostring(level)
  return { keyword = keyword, capture_type = "class", display = text, icon = HEADING_ICONS[level] }
end

local function parse_atx_heading(line_text)
  local cleaned = strip_blockquote_prefix(line_text)
  local hashes, title = cleaned:match("^(#+)%s*(.-)%s*#*$")
  if not hashes then
    return nil
  end

  local level = #hashes
  if level < 1 or level > 6 then
    return nil
  end

  title = vim.trim(title or "")
  if title == "" then
    return nil
  end

  return heading_symbol(level, title)
end

local function parse_setext_heading(line_text, line_nr, all_lines)
  if type(line_nr) ~= "number" or type(all_lines) ~= "table" then
    return nil
  end

  local next_line = all_lines[line_nr + 1]
  if not next_line then
    return nil
  end

  local underline = strip_blockquote_prefix(vim.trim(next_line))
  local level = nil
  if underline:match("^=+$") then
    level = 1
  elseif underline:match("^-+$") then
    level = 2
  end

  if not level then
    return nil
  end

  local title = vim.trim(strip_blockquote_prefix(line_text))
  if title == "" then
    return nil
  end

  return heading_symbol(level, title)
end

local function code_fence_symbol(fence_line)
  if not fence_line or not fence_line.opening then
    return nil
  end

  local label = "code"
  local info = fence_line.info or ""
  if info ~= "" then
    local lang = info:match("^(%S+)")
    if lang and lang ~= "" then
      label = "code " .. lang
    end
  end

  return { keyword = "code", capture_type = "function", display = label }
end

local function file_basename(path)
  if type(path) ~= "string" or path == "" then
    return ""
  end
  local cleaned = path:gsub("[?#].*$", "")
  local name = cleaned:match("([^/\\]+)$")
  return name or cleaned
end

local function image_symbol(line_text)
  local cleaned = strip_blockquote_prefix(line_text)
  local alt, target = cleaned:match("^!%[(.-)%]%(([^)%s]+)")
  if not alt then
    alt, target = cleaned:match("^!%[(.-)%]%[(.-)%]")
  end
  if not alt then
    return nil
  end

  local label = normalize_text(alt)
  if label == "" then
    label = normalize_text(file_basename(target or ""))
  end
  if label == "" then
    label = "image"
  end

  return { keyword = "image", capture_type = "variable", display = label, icon = IMAGE_ICON }
end

local function find_inline_link(text)
  local start_pos = 1
  while true do
    local s, e, label, url = text:find("%[(.-)%]%(([^)%s]+)", start_pos)
    if not s then
      return nil
    end
    if s == 1 or text:sub(s - 1, s - 1) ~= "!" then
      return label, url
    end
    start_pos = e + 1
  end
end

local function find_reference_link(text)
  local start_pos = 1
  while true do
    local s, e, label, ref = text:find("%[(.-)%]%[([^%]]*)%]", start_pos)
    if not s then
      return nil
    end
    if s == 1 or text:sub(s - 1, s - 1) ~= "!" then
      return label, ref
    end
    start_pos = e + 1
  end
end

local function link_symbol(line_text)
  local cleaned = strip_blockquote_prefix(line_text)
  local label, target = find_inline_link(cleaned)
  if label then
    local link_label = normalize_text(label)
    if link_label == "" then
      link_label = normalize_text(file_basename(target or ""))
    end
    if link_label == "" then
      link_label = "link"
    end
    return { keyword = "link", capture_type = "variable", display = link_label, icon = LINK_ICON }
  end

  label, target = find_reference_link(cleaned)
  if label then
    local link_label = normalize_text(label)
    if link_label == "" then
      link_label = normalize_text(target or "")
    end
    if link_label == "" then
      link_label = "link"
    end
    return { keyword = "link", capture_type = "variable", display = link_label, icon = LINK_ICON }
  end

  return nil
end

local function html_tag_symbol(line_text)
  local cleaned = strip_blockquote_prefix(line_text)
  if not cleaned:match("^<") then
    return nil
  end

  if cleaned:match("^</") or cleaned:match("^<!") or cleaned:match("^%?") then
    return nil
  end

  local tag = cleaned:match("^<%s*([%w:_-]+)")
  if not tag or tag == "" then
    return nil
  end

  return { keyword = "html", capture_type = "class", display = "<" .. tag .. ">", icon = HTML_ICON }
end

---Parse a Markdown line into a heading symbol entry.
---@param line_text string
---@param line_nr integer|nil
---@param all_lines string[]|nil
---@return {keyword:string, capture_type:string, display:string}|nil
function M.parse_symbol(line_text, line_nr, all_lines)
  if type(line_text) ~= "string" or line_text == "" then
    return nil
  end

  local trimmed = vim.trim(line_text)
  if trimmed == "" then
    return nil
  end

  if type(line_nr) == "number" and type(all_lines) == "table" then
    local fence_info = get_fence_info(all_lines)
    if fence_info then
      local fence_line = fence_info.fence[line_nr]
      if fence_line then
        return code_fence_symbol(fence_line)
      end
      if fence_info.inside[line_nr] then
        return nil
      end
    end
  end

  -- Avoid rendering the underline line for setext headings.
  if trimmed:match("^=+$") or trimmed:match("^-+$") then
    return nil
  end

  local symbol = parse_atx_heading(trimmed)
  if symbol then
    return symbol
  end

  symbol = parse_setext_heading(trimmed, line_nr, all_lines)
  if symbol then
    return symbol
  end

  local html = html_tag_symbol(trimmed)
  if html then
    return html
  end

  local image = image_symbol(trimmed)
  if image then
    return image
  end

  local link = link_symbol(trimmed)
  if link then
    return link
  end

  return nil
end

return M
