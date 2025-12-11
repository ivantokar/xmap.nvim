-- lua/xmap/treesitter.lua
-- Tree-sitter integration for xmap.nvim

local M = {}

-- Check if nvim-treesitter is available
M.available = false

-- Tree-sitter queries for Swift
M.queries = {
  swift = [[
    (class_declaration) @class
    (struct_declaration) @struct
    (protocol_declaration) @protocol
    (enum_declaration) @enum
    (extension_declaration) @extension
    (function_declaration) @function
    (init_declaration) @init
    (deinit_declaration) @deinit
    (subscript_declaration) @subscript
    (property_declaration) @property
    (comment) @comment
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

-- Get highlight group for node type
-- @param node_type string: Type of node (from capture)
-- @return string: Highlight group name
function M.get_highlight_for_type(node_type)
  local map = {
    -- Swift-specific types
    ["class"] = "XmapClass",
    ["struct"] = "XmapStruct",
    ["enum"] = "XmapEnum",
    ["protocol"] = "XmapProtocol",
    ["extension"] = "XmapExtension",
    ["function"] = "XmapFunction",
    ["init"] = "XmapInit",
    ["deinit"] = "XmapInit",
    ["method"] = "XmapMethod",
    ["property"] = "XmapProperty",
    ["subscript"] = "XmapFunction",
    ["mark"] = "XmapMark",

    -- Fallback types
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

-- Extract Swift MARK comments from buffer
-- @param bufnr number: Buffer number
-- @return table: List of MARK comments with their positions and text
function M.get_swift_marks(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return {}
  end

  local config = require("xmap.config")
  local opts = config.get()

  if not opts.swift.show_marks then
    return {}
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local marks = {}

  for line_num, line_text in ipairs(lines) do
    -- Try each MARK pattern
    for _, pattern in ipairs(opts.swift.mark_patterns) do
      local mark_text = line_text:match(pattern)
      if mark_text then
        -- Clean up the mark text
        mark_text = vim.trim(mark_text)

        -- Handle empty marks (just "MARK: -")
        if mark_text == "" or mark_text == "-" then
          mark_text = "---"
        end

        table.insert(marks, {
          line = line_num,
          text = mark_text,
          type = "mark",
        })
        break
      end
    end
  end

  return marks
end

-- Combine structural nodes and MARK comments
-- @param bufnr number: Buffer number
-- @param filetype string: Filetype
-- @return table: Combined list of nodes and marks, sorted by line
function M.get_swift_structure(bufnr, filetype)
  if filetype ~= "swift" then
    return M.get_structural_nodes(bufnr, filetype)
  end

  -- Get structural nodes
  local nodes = M.get_structural_nodes(bufnr, filetype)

  -- Get MARK comments
  local marks = M.get_swift_marks(bufnr)

  -- Convert marks to node-like structures
  for _, mark in ipairs(marks) do
    table.insert(nodes, {
      type = "mark",
      start_line = mark.line - 1,  -- Convert to 0-indexed
      start_col = 0,
      end_line = mark.line - 1,
      end_col = 0,
      mark_text = mark.text,
      node = nil,
    })
  end

  -- Sort by line number
  table.sort(nodes, function(a, b)
    return a.start_line < b.start_line
  end)

  return nodes
end

return M
