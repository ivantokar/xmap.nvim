
-- PURPOSE:
-- - Own default options and config-derived capability checks.
-- CONSTRAINTS:
-- - Filetype support requires both config opt-in and a loaded provider.

local M = {}

-- PURPOSE:
-- - Keep bundled provider filetypes in one place.
local DEFAULT_FILETYPES = { "swift", "typescript", "typescriptreact", "lua", "markdown", "c", "cpp", "h", "hpp" }

local function get_default_filetypes()
	return vim.deepcopy(DEFAULT_FILETYPES)
end
M.defaults = {
	width = 40,
	side = "right",
	auto_open = false,
	filetypes = get_default_filetypes(),
	exclude_filetypes = { "help", "terminal", "prompt", "qf", "neo-tree", "NvimTree", "lazy" },
	keymaps = {
		toggle = "<leader>mm",
		focus = "<leader>mf",
		jump = "<CR>",
		close = "q",
	},
	treesitter = {
		enable = true,
		highlight_scopes = true,
		languages = get_default_filetypes(),
	},
	symbols = {
		swift = {
			keywords = {},
			exclude = {},
			highlight_keywords = {},
		},
		typescript = {
			keywords = {},
			exclude = {},
			highlight_keywords = {},
		},
		typescriptreact = {
			keywords = {},
			exclude = {},
			highlight_keywords = {},
		},
		lua = {
			keywords = {},
			exclude = {},
			highlight_keywords = {},
		},
		markdown = {
			keywords = {},
			exclude = {},
			highlight_keywords = {},
		},
		c = {
			keywords = {},
			exclude = {},
			highlight_keywords = {},
		},
		cpp = {
			keywords = {},
			exclude = {},
			highlight_keywords = {},
		},
	},
	highlights = {},
	render = {
		relative_prefix = {
			number_width = 4,
			number_separator = " ",
			separator = " ",
			direction = {
				up = "↑",
				down = "↓",
				current = "·",
			},
		},
		max_line_length = 40,
		throttle_ms = 100,
	},
	navigation = {
		show_relative_line = true,
		auto_center = true,
		follow_cursor = true,
	},
}
M.options = {}
function M.setup(user_config)
	M.options = vim.tbl_deep_extend("force", M.defaults, user_config or {})
	return M.options
end
function M.get()
	if vim.tbl_isempty(M.options) then
		M.options = vim.deepcopy(M.defaults)
	end
	return M.options
end

function M.is_filetype_supported(filetype)
	local opts = M.get()
	if vim.tbl_contains(opts.exclude_filetypes or {}, filetype) then
		return false
	end
	if not vim.tbl_contains(opts.filetypes or get_default_filetypes(), filetype) then
		return false
	end

	local lang = require("xmap.lang")
	return lang.supports(filetype)
end

function M.is_treesitter_enabled(filetype)
	local opts = M.get()
	if not opts.treesitter.enable then
		return false
	end
	return vim.tbl_contains(opts.treesitter.languages or get_default_filetypes(), filetype)
end

return M
