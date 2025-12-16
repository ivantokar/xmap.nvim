-- lua/xmap/symbols.lua
-- Keyword configuration helpers for xmap.nvim
--
-- This module centralizes "what keywords should be visible/highlighted" logic so the core
-- rendering code doesn't need to know about configuration shapes, aliases, or precedence.
--
-- Config shape (keyed by filetype):
--   symbols = {
--     swift = {
--       -- `keywords` is an explicit allowlist. When non-empty, ONLY these will be shown.
--       keywords = { "func", "struct", "enum" },
--
--       -- `exclude` removes items from the defaults (or from the allowlist above).
--       exclude = { "let", "var" },
--
--       -- `highlight_keywords` controls which keywords are highlighted at the start of
--       -- the rendered line text. When empty, we default to the visible keyword list.
--       highlight_keywords = { "func", "struct", "enum" },
--     },
--   }
--
-- Backwards-compatible aliases:
--   - `visible_keywords` and `include` are treated like `keywords`.

local M = {}

local function is_empty(tbl)
  return not tbl or next(tbl) == nil
end

local function list_to_set(list)
  local set = {}
  for _, value in ipairs(list or {}) do
    if type(value) == "string" and value ~= "" then
      set[value] = true
    end
  end
  return set
end

local function get_lang_opts(opts, filetype)
  -- Defensive: keep callers simple by returning `{}` for any invalid input.
  if type(opts) ~= "table" or type(filetype) ~= "string" or filetype == "" then
    return {}
  end
  if type(opts.symbols) ~= "table" then
    return {}
  end
  local lang_opts = opts.symbols[filetype]
  if type(lang_opts) ~= "table" then
    return {}
  end
  return lang_opts
end

local function get_base_keywords_list(lang_opts, default_keywords)
  -- Precedence:
  -- 1) explicit allowlist (`keywords` / aliases)
  -- 2) provider defaults
  if type(lang_opts.keywords) == "table" and not is_empty(lang_opts.keywords) then
    return lang_opts.keywords
  end
  if type(lang_opts.visible_keywords) == "table" and not is_empty(lang_opts.visible_keywords) then
    return lang_opts.visible_keywords
  end
  if type(lang_opts.include) == "table" and not is_empty(lang_opts.include) then
    return lang_opts.include
  end

  return default_keywords or {}
end

---Get enabled (visible) keyword set for a filetype.
---@param opts table
---@param filetype string
---@param default_keywords string[]
---@return table<string, boolean>
function M.get_enabled_keyword_set(opts, filetype, default_keywords)
  local lang_opts = get_lang_opts(opts, filetype)
  local base = get_base_keywords_list(lang_opts, default_keywords)

  local enabled = list_to_set(base)
  if type(lang_opts.exclude) == "table" and not is_empty(lang_opts.exclude) then
    -- `exclude` is applied last so it works with both defaults and explicit allowlists.
    local exclude_set = list_to_set(lang_opts.exclude)
    for keyword in pairs(exclude_set) do
      enabled[keyword] = nil
    end
  end

  return enabled
end

---Get keywords to use for line-start keyword highlighting.
---@param opts table
---@param filetype string
---@param default_keywords string[]
---@return string[]
function M.get_highlight_keywords(opts, filetype, default_keywords)
  local lang_opts = get_lang_opts(opts, filetype)
  if type(lang_opts.highlight_keywords) == "table" and not is_empty(lang_opts.highlight_keywords) then
    return lang_opts.highlight_keywords
  end

  -- If the user provided an explicit visible keyword allowlist, default highlighting to that list.
  local base = get_base_keywords_list(lang_opts, default_keywords)
  return base or {}
end

return M
