-- PURPOSE:
-- - Resolve visible and highlighted keywords from per-language config.
-- CONSTRAINTS:
-- - Preserve backwards-compatible aliases for older config keys.

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
  -- DO:
  -- - Prefer explicit allowlists before provider defaults.
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
function M.get_enabled_keyword_set(opts, filetype, default_keywords)
  local lang_opts = get_lang_opts(opts, filetype)
  local base = get_base_keywords_list(lang_opts, default_keywords)

  local enabled = list_to_set(base)
  if type(lang_opts.exclude) == "table" and not is_empty(lang_opts.exclude) then
    -- CONSTRAINTS:
    -- - Apply `exclude` after the base list so it works for both defaults and allowlists.
    local exclude_set = list_to_set(lang_opts.exclude)
    for keyword in pairs(exclude_set) do
      enabled[keyword] = nil
    end
  end

  return enabled
end
function M.get_highlight_keywords(opts, filetype, default_keywords)
  local lang_opts = get_lang_opts(opts, filetype)
  if type(lang_opts.highlight_keywords) == "table" and not is_empty(lang_opts.highlight_keywords) then
    return lang_opts.highlight_keywords
  end
  -- DO:
  -- - Fall back to the visible keyword base when highlight-specific config is absent.
  local base = get_base_keywords_list(lang_opts, default_keywords)
  return base or {}
end

return M
