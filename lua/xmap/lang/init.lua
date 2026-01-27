-- lua/xmap/lang/init.lua
-- Language provider registry for xmap.nvim.
--
-- This module is the "plug-in point" for language-specific logic.
-- The core minimap logic (rendering, navigation, highlighting) is language-agnostic and
-- calls into a provider module when it needs to:
--   - interpret a source line as a "symbol" entry (e.g. `func foo`)
--   - decide whether a line is a comment / marker
--   - provide Tree-sitter query strings for structural highlighting
--
-- A provider module lives at: `lua/xmap/lang/<filetype>.lua`
-- where `<filetype>` matches `vim.bo.filetype` (e.g. "swift").
--
-- Provider interface (all are optional, but the minimap needs `parse_symbol` for symbols):
--   - `default_symbol_keywords` (string[]) default visible keywords for this language.
--   - `default_highlight_keywords` (string[]) keywords to highlight at line start.
--   - `get_query()` (string) primary Tree-sitter query (optional).
--   - `get_queries()` (string[]) query candidates (newest-first) for fallback parsing (optional).
--   - `parse_symbol(line_text, line_nr?, all_lines?)` -> { keyword, capture_type, display, icon? }|nil
--   - `is_comment_line(trimmed_line)` -> boolean
--   - `render_comment(line, line_nr, all_lines)` -> { kind, marker?, text? }|nil
--   - `extract_comment(line)` -> text|nil, marker|nil, is_doc_comment:boolean, raw_text|nil (optional helper)
--
-- Adding a new language does not require touching any core modules:
-- just add a provider file and list its filetype in `require("xmap").setup({ filetypes = {...} })`.

local M = {}

local providers = {}

local function load_provider(filetype)
  if type(filetype) ~= "string" or filetype == "" then
    return nil
  end

  -- Providers are loaded lazily on first use to keep startup fast.
  local ok, mod = pcall(require, "xmap.lang." .. filetype)
  if not ok or type(mod) ~= "table" then
    return nil
  end

  return mod
end

---Get the language provider for a filetype.
---@param filetype string
---@return table|nil
function M.get(filetype)
  -- Cache the result (including failures) so we don't repeatedly `require()` the same module.
  if providers[filetype] ~= nil then
    return providers[filetype] or nil
  end

  local provider = load_provider(filetype)
  providers[filetype] = provider or false
  return provider
end

---Check whether a filetype is supported by a bundled/installed provider module.
---@param filetype string
---@return boolean
function M.supports(filetype)
  return M.get(filetype) ~= nil
end

return M
