-- lua/xmap/treesitter.lua
-- Tree-sitter integration for xmap.nvim

local M = {}

-- Check if nvim-treesitter is available
M.available = false

-- Tree-sitter queries for different node types
-- These queries identify structural elements like functions, classes, etc.
M.queries = {
  -- Swift-specific queries
  -- Note: Using only confirmed node types from Swift Tree-sitter parser
  swift = [[
    (class_declaration) @class
    (function_declaration) @function
    (init_declaration) @function
    (property_declaration) @variable
  ]],

  -- Lua queries
  lua = [[
    (function_declaration) @function
    (function_definition) @function
    (assignment_statement) @variable
    (local_variable_declaration) @variable
  ]],

  -- TypeScript/JavaScript queries
  typescript = [[
    (class_declaration) @class
    (interface_declaration) @class
    (function_declaration) @function
    (method_definition) @function
    (arrow_function) @function
    (variable_declarator) @variable
  ]],

  javascript = [[
    (class_declaration) @class
    (function_declaration) @function
    (method_definition) @function
    (arrow_function) @function
    (variable_declarator) @variable
  ]],

  -- Python queries
  python = [[
    (class_definition) @class
    (function_definition) @function
    (assignment) @variable
  ]],

  -- Rust queries
  rust = [[
    (struct_item) @class
    (enum_item) @class
    (impl_item) @class
    (trait_item) @class
    (function_item) @function
    (let_declaration) @variable
  ]],

  -- Go queries
  go = [[
    (type_declaration) @class
    (function_declaration) @function
    (method_declaration) @function
    (var_declaration) @variable
  ]],

  -- C/C++ queries
  c = [[
    (struct_specifier) @class
    (function_definition) @function
    (declaration) @variable
  ]],

  cpp = [[
    (class_specifier) @class
    (struct_specifier) @class
    (function_definition) @function
    (declaration) @variable
  ]],
}

-- Initialize Tree-sitter integration
function M.setup()
  -- Check if nvim-treesitter is installed
  local ok, _ = pcall(require, "nvim-treesitter")
  M.available = ok

  if not M.available then
    vim.notify("xmap.nvim: nvim-treesitter not found. Tree-sitter features disabled.", vim.log.levels.WARN)
  end

  return M.available
end

-- Get parser for buffer
-- @param bufnr number: Buffer number
-- @return parser|nil: Tree-sitter parser or nil if not available
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

-- Get syntax tree for buffer
-- @param bufnr number: Buffer number
-- @return tree|nil: Syntax tree or nil if not available
function M.get_tree(bufnr)
  local parser = M.get_parser(bufnr)
  if not parser then
    return nil
  end

  local trees = parser:parse()
  return trees and trees[1] or nil
end

-- Extract structural nodes (functions, classes, etc.) from buffer
-- @param bufnr number: Buffer number
-- @param filetype string: Filetype
-- @return table: List of nodes with their positions and types
function M.get_structural_nodes(bufnr, filetype)
  if not M.available then
    return {}
  end

  -- Get query for this filetype
  local query_string = M.queries[filetype]
  if not query_string then
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

  -- Parse the query
  local ok, query = pcall(vim.treesitter.query.parse, filetype, query_string)
  if not ok or not query then
    -- Only show error once
    if not M._query_error_shown then
      vim.notify(
        string.format("xmap.nvim: Failed to parse Tree-sitter query for %s", filetype),
        vim.log.levels.WARN
      )
      M._query_error_shown = true
    end
    return {}
  end

  local nodes = {}
  local root = tree:root()

  -- Execute query and collect nodes
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

  -- Sort by start line
  table.sort(nodes, function(a, b)
    return a.start_line < b.start_line
  end)

  return nodes
end

-- Get the current scope/function at a given line
-- @param bufnr number: Buffer number
-- @param filetype string: Filetype
-- @param line number: Line number (0-indexed)
-- @return table|nil: Node containing the line, or nil
function M.get_scope_at_line(bufnr, filetype, line)
  local nodes = M.get_structural_nodes(bufnr, filetype)

  -- Find the smallest scope containing this line
  local current_scope = nil
  local smallest_range = math.huge

  for _, node in ipairs(nodes) do
    if node.start_line <= line and line <= node.end_line then
      local range = node.end_line - node.start_line
      if range < smallest_range then
        smallest_range = range
        current_scope = node
      end
    end
  end

  return current_scope
end

-- Get icon for node type
-- @param node_type string: Type of node (from capture)
-- @return string: Nerd Font icon
function M.get_icon_for_type(node_type)
  local map = {
    ["class"] = "",
    ["function"] = "",
    ["method"] = "",
    ["variable"] = "",
    ["comment"] = "",
  }

  return map[node_type] or ""
end

-- Get highlight group for node type
-- @param node_type string: Type of node (from capture)
-- @return string: Highlight group name
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

-- Check if Tree-sitter parser is available for filetype
-- @param filetype string: Filetype to check
-- @return boolean: True if parser is available
function M.has_parser(filetype)
  if not M.available then
    return false
  end

  local ok = pcall(vim.treesitter.get_string_parser, "", filetype)
  return ok
end

return M
