-- lua/xmap/highlight.lua
-- Highlight group management for xmap.nvim
--
-- Highlights are a big part of xmap's UX. The goals here are:
--   - Respect the active colorscheme by linking to existing groups by default.
--   - Provide safe fallbacks when a theme doesn't define a linked group.
--   - Allow user overrides via `require("xmap").setup({ highlights = { ... } })`.
--   - Keep overrides stable across `:colorscheme` by re-applying on ColorScheme.

local config = require("xmap.config")

local M = {}

-- Define all highlight groups used by xmap
-- These are the only highlight group names xmap will ever set.
M.groups = {
	-- Minimap window background
	XmapBackground = { link = "Normal" },

	-- Normal text in minimap (slightly dimmed)
	XmapText = { link = "Comment" },

	-- Line numbers in minimap (if enabled)
	XmapLineNr = { link = "LineNr" },

	-- Current viewport region (visible area in main buffer)
	XmapViewport = { link = "Visual", no_fg = true },

	-- Cursor/selection in minimap
	XmapCursor = { link = "CursorLine", no_fg = true },

	-- Tree-sitter scope highlights (will inherit from colorscheme or use fallback)
	XmapFunction = { link = "@function" },
	XmapClass = { link = "@type" },
	XmapMethod = { link = "@method" },
	XmapVariable = { link = "@variable" },
	XmapSwiftKeyword = { link = "@keyword" },
	XmapComment = { link = "Comment" },
	XmapString = { link = "String" },
	XmapNumber = { link = "Number" },

	-- Structural indicators
	XmapScope = { link = "Title" },
	XmapBorder = { link = "FloatBorder" },

	-- Relative distance + direction prefix (derive from theme groups by default).
	-- Used by `minimap.apply_relative_number_highlighting`.
	XmapRelativeUp = { link = "DiagnosticOk", bold = true, no_bg = true },
	XmapRelativeDown = { link = "DiagnosticError", bold = true, no_bg = true },
	XmapRelativeCurrent = { link = "DiagnosticWarn", bold = true, no_bg = true },
	XmapRelativeNumber = { link = "CursorLineNr", bold = false, no_bg = true }, -- Brighter numbers by default
	XmapRelativeKeyword = { link = "Keyword", bold = true, no_bg = true },
	XmapRelativeEntity = { link = "Identifier", no_bg = true },

	-- Comment markers
	XmapCommentNormal = { link = "Comment", no_bg = true }, -- Regular comments
	XmapCommentDoc = { link = "SpecialComment", no_bg = true }, -- Doc comments (///)
	XmapCommentBold = { bold = true, no_bg = true }, -- Bold text for marker descriptions
	XmapCommentMark = { link = "WarningMsg", bold = true, no_bg = true }, -- MARK: marker
	XmapCommentTodo = { link = "WarningMsg", bold = true, no_bg = true }, -- TODO: marker
	XmapCommentFixme = { link = "WarningMsg", bold = true, no_bg = true }, -- FIXME: marker
	XmapCommentNote = { link = "WarningMsg", bold = true, no_bg = true }, -- NOTE: marker
	XmapCommentWarning = { link = "WarningMsg", bold = true, no_bg = true }, -- WARNING: marker
	XmapCommentBug = { link = "WarningMsg", bold = true, no_bg = true }, -- BUG: marker
}

-- Fallback colors (used only if a linked group does not exist or resolves to empty).
-- Keep these conservative: the intention is "still readable", not "force a theme".
local fallback_colors = {
	XmapFunction = { fg = "#7aa2f7", bold = true }, -- Blue
	XmapClass = { fg = "#bb9af7", bold = true }, -- Purple
	XmapVariable = { fg = "#9ece6a" }, -- Green
	XmapSwiftKeyword = { fg = "#bb9af7" }, -- Purple
	XmapRelativeUp = { fg = "#9ece6a", bold = true }, -- Green
	XmapRelativeDown = { fg = "#f7768e", bold = true }, -- Red
	XmapRelativeCurrent = { fg = "#e0af68", bold = true }, -- Yellow
	XmapRelativeNumber = { fg = "#c0caf5", bold = true }, -- Bright
	XmapRelativeKeyword = { fg = "#bb9af7", bold = true }, -- Purple (keywords)
	XmapRelativeEntity = { fg = "#7dcfff" }, -- Cyan (entity names)
}

local function is_empty(tbl)
	return not tbl or next(tbl) == nil
end

local function get_resolved_hl(name)
	-- Request the fully-resolved highlight definition (no link indirection). If a theme
	-- does not define the group, Neovim returns an empty table.
	local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
	if not ok or is_empty(hl) then
		return nil
	end
	return hl
end

local function apply_overrides(base, overrides)
	-- Merge highlight definitions while supporting our convenience flags:
	--   - `no_bg`: clear background even when the linked group has one
	--   - `no_fg`: clear foreground even when the linked group has one
	local out = vim.deepcopy(base or {})
	for k, v in pairs(overrides or {}) do
		if k ~= "link" and k ~= "no_bg" and k ~= "no_fg" then
			out[k] = v
		end
	end
	if overrides and overrides.no_bg then
		out.bg = nil
		out.ctermbg = nil
	end
	if overrides and overrides.no_fg then
		out.fg = nil
		out.ctermfg = nil
	end
	return out
end

local function clamp_byte(value)
	if value < 0 then
		return 0
	end
	if value > 255 then
		return 255
	end
	return value
end

local function rgb_from_int(color)
	local r = math.floor(color / 0x10000) % 0x100
	local g = math.floor(color / 0x100) % 0x100
	local b = color % 0x100
	return r, g, b
end

local function int_from_rgb(r, g, b)
	return r * 0x10000 + g * 0x100 + b
end

local function color_luminance(color)
	local r, g, b = rgb_from_int(color)
	return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
end

local function adjust_color(color, amount)
	local r, g, b = rgb_from_int(color)
	local function adjust(channel)
		if amount >= 0 then
			return clamp_byte(math.floor(channel + (255 - channel) * amount + 0.5))
		end
		return clamp_byte(math.floor(channel * (1 + amount) + 0.5))
	end
	return int_from_rgb(adjust(r), adjust(g), adjust(b))
end

local function derive_cursor_bg()
	-- Derive a visible cursor background color when the colorscheme doesn't provide one.
	-- Many transparent themes leave CursorLine.bg unset, so we try a few options:
	--   1) CursorLine.bg
	--   2) Visual.bg (often a good contrast)
	--   3) a slight luminance adjustment of Normal.bg
	local cursor = get_resolved_hl("CursorLine")
	local visual = get_resolved_hl("Visual")
	local normal = get_resolved_hl("Normal")

	local normal_bg = normal and normal.bg or nil

	local bg = cursor and cursor.bg or nil
	if not bg or (normal_bg and bg == normal_bg) then
		local visual_bg = visual and visual.bg or nil
		if visual_bg and (not normal_bg or visual_bg ~= normal_bg) then
			bg = visual_bg
		end
	end

	if not bg and normal_bg then
		local lum = color_luminance(normal_bg)
		bg = adjust_color(normal_bg, lum < 0.5 and 0.08 or -0.08)
	end

	return bg
end

local function get_highlight_overrides()
	-- User overrides live in config (`opts.highlights`). We read them here so `M.setup()`
	-- can reapply everything on demand (e.g. after ColorScheme).
	local opts = config.get()
	if type(opts.highlights) ~= "table" then
		return {}
	end
	return opts.highlights
end

local function normalize_override(value)
	-- Convenience: allow both
	--   highlights = { XmapText = "Comment" }
	-- and
	--   highlights = { XmapText = { link = "Comment", italic = true } }
	if type(value) == "string" then
		return { link = value }
	end
	if type(value) == "table" then
		return value
	end
	return nil
end

-- Setup highlight groups
function M.setup()
	-- Called on plugin setup and on ColorScheme changes.
	-- For each group:
	--   - resolve the linked highlight (if it exists)
	--   - apply fallback colors when missing
	--   - layer user overrides on top
	local overrides = get_highlight_overrides()
	for group_name, group_def in pairs(M.groups) do
		local user_override = normalize_override(overrides[group_name])
		local def = group_def
		if user_override then
			def = vim.tbl_deep_extend("force", {}, group_def, user_override)
		end

		if group_name == "XmapCursor" and def.link then
			-- Special-case: ensure the minimap cursor highlight is visible even on
			-- transparent themes where CursorLine has no bg.
			local link_name = def.link
			local link_hl = get_resolved_hl(link_name) or {}
			local resolved = apply_overrides(link_hl, def)

			local normal = get_resolved_hl("Normal")
			local normal_bg = normal and normal.bg or nil

			if not resolved.bg or (normal_bg and resolved.bg == normal_bg) then
				resolved.bg = derive_cursor_bg()
				if not resolved.bg then
					resolved.reverse = true
				end
			end

			vim.api.nvim_set_hl(0, group_name, resolved)
		elseif def.link then
			local link_name = def.link
			local link_hl = get_resolved_hl(link_name)
			if link_hl then
				vim.api.nvim_set_hl(0, group_name, apply_overrides(link_hl, def))
			elseif fallback_colors[group_name] then
				vim.api.nvim_set_hl(0, group_name, apply_overrides(fallback_colors[group_name], def))
			else
				vim.api.nvim_set_hl(0, group_name, apply_overrides({ link = link_name }, def))
			end
		else
			vim.api.nvim_set_hl(0, group_name, apply_overrides({}, def))
		end
	end
end

-- Apply highlight to a buffer region
-- @param bufnr number: Buffer number
-- @param ns_id number: Namespace ID
-- @param hl_group string: Highlight group name
-- @param line number: Line number (0-indexed)
-- @param col_start number: Start column (0-indexed)
-- @param col_end number: End column (-1 for end of line)
function M.apply(bufnr, ns_id, hl_group, line, col_start, col_end)
	-- Highlights are best-effort. A bad range should not break the minimap update loop.
	pcall(vim.api.nvim_buf_add_highlight, bufnr, ns_id, hl_group, line, col_start, col_end)
end

-- Clear highlights in buffer
function M.clear(bufnr, ns_id, line_start, line_end)
	-- Clear an entire namespace (or a range) before re-applying highlights.
	line_start = line_start or 0
	line_end = line_end or -1
	pcall(vim.api.nvim_buf_clear_namespace, bufnr, ns_id, line_start, line_end)
end

-- Create a namespace for xmap highlights
function M.create_namespace(name)
	-- Namespaces isolate different highlight layers (viewport/cursor/syntax/structure)
	-- so they can be cleared independently.
	return vim.api.nvim_create_namespace("xmap_" .. name)
end

-- Refresh all highlight groups (useful when colorscheme changes)
function M.refresh()
	M.setup()
end

return M
