-- PURPOSE:
-- - Hide optional Tree-sitter integration behind a small cached API.
-- CONSTRAINTS:
-- - Query strings come from language providers, not this module.

local M = {}
M.available = false

local lang = require("xmap.lang")

M._compiled_queries = {}
M._query_error_shown = {}

local function is_non_empty_string(value)
  return type(value) == "string" and value ~= ""
end

local function resolve_treesitter_language(filetype)
  if type(filetype) ~= "string" or filetype == "" then
    return filetype
  end

  local ok, lang = pcall(function()
    if vim.treesitter and vim.treesitter.language and vim.treesitter.language.get_lang then
      return vim.treesitter.language.get_lang(filetype)
    end
    return nil
  end)

  if ok and is_non_empty_string(lang) then
    return lang
  end

  return filetype
end

local function get_query_candidates(filetype)
  -- PURPOSE:
  -- - Accept provider query fallbacks without hard-coding provider shapes downstream.
  local provider = lang.get(filetype)
  if not provider then
    return {}
  end

  if type(provider.get_queries) == "function" then
    local ok, queries = pcall(provider.get_queries)
    if ok and type(queries) == "table" then
      return queries
    end
  end

  if type(provider.get_query) == "function" then
    local ok, query_string = pcall(provider.get_query)
    if ok and is_non_empty_string(query_string) then
      return { query_string }
    end
  end

  return {}
end

local function get_compiled_query(filetype)
  -- CONSTRAINTS:
  -- - Cache failed lookups as `false` to avoid repeated parse work and warnings.
  if M._compiled_queries[filetype] ~= nil then
    return M._compiled_queries[filetype] or nil
  end

  local candidates = get_query_candidates(filetype)
  local last_error = nil
  local ts_lang = resolve_treesitter_language(filetype)

  for _, query_string in ipairs(candidates) do
    if is_non_empty_string(query_string) then
      local ok, query_or_err = pcall(vim.treesitter.query.parse, ts_lang, query_string)
      if ok and query_or_err then
        M._compiled_queries[filetype] = query_or_err
        return query_or_err
      end
      if not ok then
        last_error = query_or_err
      end
    end
  end

  M._compiled_queries[filetype] = false
  return nil, last_error
end
function M.setup()
  local ok, _ = pcall(require, "nvim-treesitter")
  M.available = ok

  M._compiled_queries = {}
  M._query_error_shown = {}

  if not M.available then
    vim.notify("xmap.nvim: nvim-treesitter not found. Tree-sitter features disabled.", vim.log.levels.WARN)
  end

  return M.available
end
function M.get_parser(bufnr)
  if not M.available then
    return nil
  end

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return nil
  end

  return parser
end
function M.get_tree(bufnr)
  local parser = M.get_parser(bufnr)
  if not parser then
    return nil
  end

  local trees = parser:parse()
  return trees and trees[1] or nil
end
function M.get_structural_nodes(bufnr, filetype)
  if not M.available then
    return {}
  end

  local parser = M.get_parser(bufnr)
  if not parser then
    return {}
  end

  local tree = M.get_tree(bufnr)
  if not tree then
    return {}
  end

  local query, last_error = get_compiled_query(filetype)
  if not query then
    -- DO:
    -- - Warn once per filetype.
    if not M._query_error_shown[filetype] then
      vim.notify(string.format("xmap.nvim: Failed to parse Tree-sitter query for %s", filetype), vim.log.levels.WARN)
      M._query_error_shown[filetype] = true
    end
    return {}
  end

  local nodes = {}
  local root = tree:root()
  for id, node in query:iter_captures(root, bufnr, 0, -1) do
    local capture_name = query.captures[id]
    local start_row, start_col, end_row, end_col = node:range()
    table.insert(nodes, {
      type = capture_name,
      start_line = start_row,
      start_col = start_col,
      end_line = end_row,
      end_col = end_col,
      node = node,
    })
  end
  table.sort(nodes, function(a, b)
    return a.start_line < b.start_line
  end)

  return nodes
end
function M.get_scope_at_line(bufnr, filetype, line)
  local nodes = M.get_structural_nodes(bufnr, filetype)
  local current_scope = nil
  local smallest_range = math.huge

  for _, node in ipairs(nodes) do
    if node.start_line <= line and line <= node.end_line then
      -- ALGORITHM:
      -- - Prefer the smallest enclosing node as the active scope.
      local range = node.end_line - node.start_line
      if range < smallest_range then
        smallest_range = range
        current_scope = node
      end
    end
  end

  return current_scope
end
function M.get_icon_for_type(node_type)
  local map = {
    ["class"] = "󰠱",
    ["function"] = "󰊕",
    ["method"] = "󰆧",
    ["variable"] = "󰀫",
    ["comment"] = "󰆈",
  }

  return map[node_type] or ""
end
function M.get_highlight_for_type(node_type)
  local map = {
    ["class"] = "XmapClass",
    ["function"] = "XmapFunction",
    ["method"] = "XmapMethod",
    ["variable"] = "XmapVariable",
    ["comment"] = "XmapComment",
  }

  return map[node_type] or "XmapText"
end
function M.has_parser(filetype)
  if not M.available then
    return false
  end

  local ts_lang = resolve_treesitter_language(filetype)
  local ok = pcall(vim.treesitter.get_string_parser, "", ts_lang)
  return ok
end

return M
