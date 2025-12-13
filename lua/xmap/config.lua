-- lua/xmap/config.lua
-- Configuration management for xmap.nvim

local M = {}

-- Canonical list of languages supported out of the box
local DEFAULT_LANGUAGES = {
	"swift",
	"lua",
	"typescript",
	"javascript",
	"python",
	"rust",
	"go",
	"c",
	"cpp",
}

-- Return a fresh copy so callers can't mutate the canonical defaults
local function get_default_languages()
	return vim.deepcopy(DEFAULT_LANGUAGES)
end

-- Default configuration
M.defaults = {
	-- Window settings
	width = 40, -- Width of the minimap window (for relative numbers + icons + text)
	side = "right", -- "right" or "left"
	auto_open = false, -- Automatically open minimap for supported filetypes

	-- Filetypes where minimap should be enabled (multi-language by default)
	filetypes = get_default_languages(),

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
		languages = get_default_languages(),
	},

	-- Rendering options
	render = {
		-- How to render each line:
		-- "compact" - use simplified blocks/characters
		-- "text" - use truncated actual text with icons
		mode = "text",

		-- Maximum number of characters per line in minimap (including prefix)
		max_line_length = 40,

		-- Show line numbers in minimap
		show_line_numbers = false,

		-- Viewport indicator character
		viewport_char = "█",

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
	local opts = M.get()

	-- Check if in exclude list
	if vim.tbl_contains(opts.exclude_filetypes or {}, filetype) then
		return false
	end

	-- Check if in include list
	return vim.tbl_contains(opts.filetypes or get_default_languages(), filetype)
end

-- Check if Tree-sitter is enabled for current language
function M.is_treesitter_enabled(filetype)
	local opts = M.get()
	if not opts.treesitter.enable then
		return false
	end
	return vim.tbl_contains(opts.treesitter.languages or get_default_languages(), filetype)
end

-- Expose default languages for reuse without exposing the internal table
function M.get_default_languages()
	return get_default_languages()
end

return M
