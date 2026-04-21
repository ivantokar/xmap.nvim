-- AI HINTS: lua/xmap/config.lua
-- AI HINTS: Copyright (c) Ivan Tokar. MIT License.
-- PURPOSE: Centralize config defaults + runtime config checks for xmap.
-- OUTPUT: Stable config table via `get()`, support predicates via helper APIs.
-- DEPENDENCIES: `xmap.lang` provider registry for filetype availability checks.
-- CONSTRAINTS: Config module must not open/close windows or mutate editor layout.
-- STABILITY: Core

local M = {}

-- PURPOSE: Built-in provider filetypes.
-- AI HINTS: Add new filetypes only with matching provider module at `lua/xmap/lang/<filetype>.lua`.
local DEFAULT_FILETYPES = { "swift", "typescript", "typescriptreact", "lua", "markdown", "c", "cpp", "h", "hpp" }

local function get_default_filetypes()
	return vim.deepcopy(DEFAULT_FILETYPES)
end

-- AI HINTS: Default configuration
M.defaults = {
	-- AI HINTS: Window settings
	width = 40, -- AI HINTS: Width of the minimap window (for relative numbers + icons + text)
	side = "right", -- AI HINTS: "right" or "left" (pinned to tabpage edge)
	auto_open = false, -- AI HINTS: Automatically open minimap for supported filetypes

	-- AI HINTS: Filetypes where minimap should be enabled
	filetypes = get_default_filetypes(),

	-- AI HINTS: Filetypes to exclude
	exclude_filetypes = { "help", "terminal", "prompt", "qf", "neo-tree", "NvimTree", "lazy" },

	-- AI HINTS: Keymaps (set to false to disable default mappings)
	keymaps = {
		toggle = "<leader>mm", -- AI HINTS: Toggle minimap
		focus = "<leader>mf", -- AI HINTS: Focus minimap window
		jump = "<CR>", -- AI HINTS: Jump to line (inside minimap)
		close = "q", -- AI HINTS: Close minimap (inside minimap)
	},

	-- AI HINTS: Tree-sitter integration
	treesitter = {
		enable = true, -- AI HINTS: Enable Tree-sitter integration
		highlight_scopes = true, -- AI HINTS: Highlight structural scopes (functions, classes, etc.)
		-- AI HINTS: Enable Tree-sitter per filetype. This is separate from `filetypes` so you can
		-- AI HINTS: keep xmap enabled but disable Tree-sitter (or vice versa) per language.
		languages = get_default_filetypes(),
	},

	-- AI HINTS: Symbol filtering per language (keyed by filetype)
	-- AI HINTS: For Swift, this controls which declaration keywords are shown in the minimap.
	-- AI HINTS: Example: hide properties but keep types + functions:
	-- AI HINTS: symbols = { swift = { exclude = { "let", "var" } } }
	symbols = {
		swift = {
			keywords = {}, -- AI HINTS: When empty, uses the Swift provider defaults
			exclude = {}, -- AI HINTS: Keywords to hide (e.g. { "let", "var" })
			highlight_keywords = {}, -- AI HINTS: Optional override for keyword highlighting list
		},
		typescript = {
			keywords = {}, -- AI HINTS: When empty, uses the TypeScript provider defaults
			exclude = {},
			highlight_keywords = {},
		},
		typescriptreact = {
			keywords = {}, -- AI HINTS: When empty, uses the TSX provider defaults (TypeScript + React hooks)
			exclude = {},
			highlight_keywords = {},
		},
		lua = {
			keywords = {}, -- AI HINTS: When empty, uses the Lua provider defaults
			exclude = {},
			highlight_keywords = {},
		},
		markdown = {
			keywords = {}, -- AI HINTS: When empty, uses the Markdown provider defaults (H1-H6)
			exclude = {},
			highlight_keywords = {},
		},
		c = {
			-- AI HINTS: Empty keyword/highlight arrays intentionally defer to provider-level
			-- AI HINTS: defaults from `lua/xmap/lang/c.lua`.
			keywords = {}, -- AI HINTS: When empty, uses the C provider defaults
			exclude = {},
			highlight_keywords = {},
		},
		cpp = {
			-- AI HINTS: Empty keyword/highlight arrays intentionally defer to provider-level
			-- AI HINTS: defaults from `lua/xmap/lang/cpp.lua`.
			keywords = {}, -- AI HINTS: When empty, uses the C++ provider defaults
			exclude = {},
			highlight_keywords = {},
		},
	},

	-- AI HINTS: Highlight overrides (applied on setup and on ColorScheme refresh)
	-- AI HINTS: Example:
	-- AI HINTS: highlights = { XmapRelativeNumber = { link = "CursorLineNr", bold = true } }
	highlights = {},

	-- AI HINTS: Rendering options
	render = {
		-- AI HINTS: Relative prefix (distance + direction) shown for each minimap line.
		-- AI HINTS: Default format: ` 12 ↓ ` (number first, direction after).
		relative_prefix = {
			-- AI HINTS: Minimum width (in digits) for the distance column.
			-- AI HINTS: Distances are capped at 999 for consistent alignment.
			number_width = 4,
			-- AI HINTS: Inserted between the number and the direction indicator.
			-- AI HINTS: Example: number_separator=" " produces `12 ↓`, number_separator="" produces `12↓`.
			number_separator = " ",
			-- AI HINTS: Inserted after the direction indicator (before icon/text).
			-- AI HINTS: Example: separator=" " produces `↓ 󰊕 func foo`.
			separator = " ",
			-- AI HINTS: Direction indicators can be symbols or key letters (e.g. down="j", up="k").
			direction = {
				up = "↑",
				down = "↓",
				current = "·",
			},
		},

		-- AI HINTS: Maximum number of characters per line in minimap (including prefix)
		max_line_length = 40,

		-- AI HINTS: Update frequency (milliseconds)
		-- AI HINTS: Throttle minimap updates to avoid performance issues
		throttle_ms = 100,
	},

	-- AI HINTS: Navigation settings
	navigation = {
		-- AI HINTS: Show relative line indicator when navigating
		show_relative_line = true,

		-- AI HINTS: Auto-center main window when jumping
		auto_center = true,

		-- AI HINTS: While the minimap is focused, keep the main editor cursor centered on the minimap selection.
		follow_cursor = true,
	},
}

-- AI HINTS: Current user configuration
M.options = {}

-- PURPOSE: Merge user options over defaults.
function M.setup(user_config)
	M.options = vim.tbl_deep_extend("force", M.defaults, user_config or {})
	return M.options
end

-- AI HINTS: Get current configuration
function M.get()
	if vim.tbl_isempty(M.options) then
		M.options = vim.deepcopy(M.defaults)
	end
	return M.options
end

function M.is_filetype_supported(filetype)
	-- PURPOSE: Return true only when filetype is allowed by config and provider exists.
	-- CONSTRAINTS: Require both include-list membership and provider availability.
	local opts = M.get()

	-- AI HINTS: Check if in exclude list
	if vim.tbl_contains(opts.exclude_filetypes or {}, filetype) then
		return false
	end

	-- AI HINTS: Check if in include list
	if not vim.tbl_contains(opts.filetypes or get_default_filetypes(), filetype) then
		return false
	end

	local lang = require("xmap.lang")
	return lang.supports(filetype)
end

function M.is_treesitter_enabled(filetype)
	-- PURPOSE: Return true only when Tree-sitter is globally enabled and filetype is allowed.
	local opts = M.get()
	if not opts.treesitter.enable then
		return false
	end
	return vim.tbl_contains(opts.treesitter.languages or get_default_filetypes(), filetype)
end

return M
