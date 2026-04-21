-- AI HINTS: lua/xmap/lang/init.lua
-- AI HINTS: Copyright (c) Ivan Tokar. MIT License.
-- AI HINTS: Language provider registry for xmap.nvim.
--
-- AI HINTS: This module is the "plug-in point" for language-specific logic.
-- AI HINTS: The core minimap logic (rendering, navigation, highlighting) is language-agnostic and
-- AI HINTS: calls into a provider module when it needs to:
-- AI HINTS: - interpret a source line as a "symbol" entry (e.g. `func foo`)
-- AI HINTS: - decide whether a line is a comment / marker
-- AI HINTS: - provide Tree-sitter query strings for structural highlighting
--
-- AI HINTS: A provider module lives at: `lua/xmap/lang/<filetype>.lua`
-- AI HINTS: where `<filetype>` matches `vim.bo.filetype` (e.g. "swift").
--
-- AI HINTS: Provider interface (all are optional, but the minimap needs `parse_symbol` for symbols):
-- AI HINTS: - `default_symbol_keywords` (string[]) default visible keywords for this language.
-- AI HINTS: - `default_highlight_keywords` (string[]) keywords to highlight at line start.
-- AI HINTS: - `get_query()` (string) primary Tree-sitter query (optional).
-- AI HINTS: - `get_queries()` (string[]) query candidates (newest-first) for fallback parsing (optional).
-- AI HINTS: - `parse_symbol(line_text, line_nr?, all_lines?)` -> { keyword, capture_type, display, icon? }|nil
-- AI HINTS: - `is_comment_line(trimmed_line)` -> boolean
-- AI HINTS: - `render_comment(line, line_nr, all_lines)` -> { kind, marker?, text? }|nil
-- AI HINTS: - `extract_comment(line)` -> text|nil, marker|nil, is_doc_comment:boolean, raw_text|nil (optional helper)
--
-- AI HINTS: Adding a new language does not require touching any core modules:
-- AI HINTS: just add a provider file and list its filetype in `require("xmap").setup({ filetypes = {...} })`.

local M = {}

local providers = {}

local function load_provider(filetype)
  if type(filetype) ~= "string" or filetype == "" then
    return nil
  end

  -- AI HINTS: Providers are loaded lazily on first use to keep startup fast.
  local ok, mod = pcall(require, "xmap.lang." .. filetype)
  if not ok or type(mod) ~= "table" then
    return nil
  end

  return mod
end

-- AI HINTS: -Get the language provider for a filetype.
-- AI HINTS: -@param filetype string
-- AI HINTS: -@return table|nil
function M.get(filetype)
  -- AI HINTS: Cache the result (including failures) so we don't repeatedly `require()` the same module.
  if providers[filetype] ~= nil then
    return providers[filetype] or nil
  end

  local provider = load_provider(filetype)
  providers[filetype] = provider or false
  return provider
end

-- AI HINTS: -Check whether a filetype is supported by a bundled/installed provider module.
-- AI HINTS: -@param filetype string
-- AI HINTS: -@return boolean
function M.supports(filetype)
  return M.get(filetype) ~= nil
end

return M
