-- lua/xmap/config.lua
-- Configuration management for xmap.nvim
--
-- Responsibilities:
--   - define default options
--   - merge user config into defaults (`setup`)
--   - answer "is this filetype supported?" (`is_filetype_supported`)
--   - answer "should Tree-sitter run for this filetype?" (`is_treesitter_enabled`)
--
-- Language support is provider-driven:
-- a filetype is supported only when it is included in `filetypes` AND a provider module exists
-- at `lua/xmap/lang/<filetype>.lua`. This keeps core logic SOLID and makes it easy to add
-- new languages later without editing core modules.

local M = {}

-- Swift-only by default. Additional languages can be added by installing/creating
-- a matching provider module under `lua/xmap/lang/<filetype>.lua` and adding the
-- filetype to `filetypes` (and `treesitter.languages` if desired).
local DEFAULT_FILETYPES = { "swift" }

local function get_default_filetypes()
	return vim.deepcopy(DEFAULT_FILETYPES)
end

-- Default configuration
M.defaults = {
	-- Window settings
	width = 40, -- Width of the minimap window (for relative numbers + icons + text)
	side = "right", -- "right" or "left"
	auto_open = false, -- Automatically open minimap for supported filetypes

	-- Filetypes where minimap should be enabled
	filetypes = get_default_filetypes(),

	-- Filetypes to exclude
	exclude_filetypes = { "help", "terminal", "prompt", "qf", "neo-tree", "NvimTree", "lazy" },

	-- Keymaps (set to false to disable default mappings)
	keymaps = {
		toggle = "<leader>mm", -- Toggle minimap
		focus = "<leader>mf", -- Focus minimap window
		jump = "<CR>", -- Jump to line (inside minimap)
		close = "q", -- Close minimap (inside minimap)
	},

	-- Tree-sitter integration
	treesitter = {
		enable = true, -- Enable Tree-sitter integration
		highlight_scopes = true, -- Highlight structural scopes (functions, classes, etc.)
		-- Enable Tree-sitter per filetype. This is separate from `filetypes` so you can
		-- keep xmap enabled but disable Tree-sitter (or vice versa) per language.
		languages = get_default_filetypes(),
	},

	-- Symbol filtering per language (keyed by filetype)
	-- For Swift, this controls which declaration keywords are shown in the minimap.
	-- Example: hide properties but keep types + functions:
	-- symbols = { swift = { exclude = { "let", "var" } } }
	symbols = {
		swift = {
			keywords = {}, -- When empty, uses the Swift provider defaults
			exclude = {}, -- Keywords to hide (e.g. { "let", "var" })
			highlight_keywords = {}, -- Optional override for keyword highlighting list
		},
	},

	-- Highlight overrides (applied on setup and on ColorScheme refresh)
	-- Example:
	-- highlights = { XmapRelativeNumber = { link = "CursorLineNr", bold = true } }
	highlights = {},

	-- Rendering options
	render = {
		-- Relative prefix (distance + direction) shown for each minimap line.
		-- Default format: ` 12 ↓ ` (number first, direction after).
		relative_prefix = {
			-- Minimum width (in digits) for the distance column.
			-- Distances are capped at 999 for consistent alignment.
			number_width = 3,
			-- Inserted between the number and the direction indicator.
			-- Example: number_separator=" " produces `12 ↓`, number_separator="" produces `12↓`.
			number_separator = " ",
			-- Inserted after the direction indicator (before icon/text).
			-- Example: separator=" " produces `↓ 󰊕 func foo`.
			separator = " ",
			-- Direction indicators can be symbols or key letters (e.g. down="j", up="k").
			direction = {
				up = "↑",
				down = "↓",
				current = "·",
			},
		},

		-- Maximum number of characters per line in minimap (including prefix)
		max_line_length = 40,

		-- Update frequency (milliseconds)
		-- Throttle minimap updates to avoid performance issues
		throttle_ms = 100,
	},

	-- Navigation settings
	navigation = {
		-- Show relative line indicator when navigating
		show_relative_line = true,

		-- Auto-center main window when jumping
		auto_center = true,

		-- While the minimap is focused, keep the main editor cursor centered on the minimap selection.
		follow_cursor = true,
	},
}

-- Current user configuration
M.options = {}

-- Setup function to merge user config with defaults
function M.setup(user_config)
	-- Deep-merge so users can override only the parts they care about.
	M.options = vim.tbl_deep_extend("force", M.defaults, user_config or {})
	return M.options
end

-- Get current configuration
function M.get()
	if vim.tbl_isempty(M.options) then
		M.options = vim.deepcopy(M.defaults)
	end
	return M.options
end

-- Check if filetype is supported
function M.is_filetype_supported(filetype)
	-- Support is a combination of user config + installed providers.
	-- This makes it possible to add new language support without editing this module.
	local opts = M.get()

	-- Check if in exclude list
	if vim.tbl_contains(opts.exclude_filetypes or {}, filetype) then
		return false
	end

	-- Check if in include list
	if not vim.tbl_contains(opts.filetypes or get_default_filetypes(), filetype) then
		return false
	end

	-- A filetype is only supported when a provider module exists (e.g. xmap.lang.swift).
	local lang = require("xmap.lang")
	return lang.supports(filetype)
end

-- Check if Tree-sitter is enabled for current language
function M.is_treesitter_enabled(filetype)
	-- Tree-sitter can be enabled/disabled globally (`treesitter.enable`) and also
	-- restricted to a subset of filetypes (`treesitter.languages`).
	local opts = M.get()
	if not opts.treesitter.enable then
		return false
	end
	return vim.tbl_contains(opts.treesitter.languages or get_default_filetypes(), filetype)
end

return M
