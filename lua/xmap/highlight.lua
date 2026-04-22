-- PURPOSE:
-- - Define xmap highlight groups and resolve theme-safe fallbacks.
-- CONSTRAINTS:
-- - Respect colorscheme links first; fall back only when the resolved group is empty.

local config = require("xmap.config")

local M = {}

-- PURPOSE:
-- - Keep the complete public highlight surface in one map.
M.groups = {
	XmapBackground = { link = "Normal" },
	XmapText = { link = "Comment" },
	XmapLineNr = { link = "LineNr" },
	XmapViewport = { link = "Visual", no_fg = true },
	XmapCursor = { link = "CursorLine", no_fg = true },
	XmapFunction = { link = "@function" },
	XmapClass = { link = "@type" },
	XmapMethod = { link = "@method" },
	XmapVariable = { link = "@variable" },
	XmapSwiftKeyword = { link = "@keyword" },
	XmapComment = { link = "Comment" },
	XmapString = { link = "String" },
	XmapNumber = { link = "Number" },
	XmapMarkdownH1 = { link = "DiagnosticError" },
	XmapMarkdownH2 = { link = "DiagnosticWarn" },
	XmapMarkdownH3 = { link = "DiagnosticOk" },
	XmapMarkdownH4 = { link = "Comment" },
	XmapMarkdownH5 = { link = "Comment" },
	XmapMarkdownH6 = { link = "Comment" },
	XmapMarkdownHeadingText = { link = "XmapText" },
	XmapScope = { link = "Title" },
	XmapBorder = { link = "FloatBorder" },
	XmapRelativeUp = { link = "DiagnosticOk", bold = true, no_bg = true },
	XmapRelativeDown = { link = "DiagnosticError", bold = true, no_bg = true },
	XmapRelativeCurrent = { link = "DiagnosticWarn", bold = true, no_bg = true },
	XmapRelativeNumber = { link = "CursorLineNr", bold = false, no_bg = true },
	XmapRelativeKeyword = { link = "Keyword", bold = true, no_bg = true },
	XmapRelativeEntity = { link = "Identifier", no_bg = true },
	XmapCommentNormal = { link = "Comment", no_bg = true },
	XmapCommentDoc = { link = "SpecialComment", no_bg = true },
	XmapCommentBold = { bold = true, no_bg = true },
	XmapCommentMark = { link = "WarningMsg", bold = true, no_bg = true },
	XmapCommentTodo = { link = "WarningMsg", bold = true, no_bg = true },
	XmapCommentFixme = { link = "WarningMsg", bold = true, no_bg = true },
	XmapCommentNote = { link = "WarningMsg", bold = true, no_bg = true },
	XmapCommentWarning = { link = "WarningMsg", bold = true, no_bg = true },
	XmapCommentBug = { link = "WarningMsg", bold = true, no_bg = true },
}
local fallback_colors = {
	XmapFunction = { fg = "#7aa2f7", bold = true },
	XmapClass = { fg = "#bb9af7", bold = true },
	XmapVariable = { fg = "#9ece6a" },
	XmapSwiftKeyword = { fg = "#bb9af7" },
	XmapRelativeUp = { fg = "#9ece6a", bold = true },
	XmapRelativeDown = { fg = "#f7768e", bold = true },
	XmapRelativeCurrent = { fg = "#e0af68", bold = true },
	XmapRelativeNumber = { fg = "#c0caf5", bold = true },
	XmapRelativeKeyword = { fg = "#bb9af7", bold = true },
	XmapRelativeEntity = { fg = "#7dcfff" },
	XmapMarkdownH1 = { fg = "#f7768e" },
	XmapMarkdownH2 = { fg = "#e0af68" },
	XmapMarkdownH3 = { fg = "#9ece6a" },
	XmapMarkdownH4 = { fg = "#565f89" },
	XmapMarkdownH5 = { fg = "#565f89" },
	XmapMarkdownH6 = { fg = "#565f89" },
}

local function is_empty(tbl)
	return not tbl or next(tbl) == nil
end

local function get_resolved_hl(name)
	local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
	if not ok or is_empty(hl) then
		return nil
	end
	return hl
end

local function apply_overrides(base, overrides)
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
	-- DO:
	-- - Prefer an existing visible theme background before synthesizing one.
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
	local opts = config.get()
	if type(opts.highlights) ~= "table" then
		return {}
	end
	return opts.highlights
end

local function normalize_override(value)
	-- PURPOSE:
	-- - Accept either `link` shorthand or a full override table.
	if type(value) == "string" then
		return { link = value }
	end
	if type(value) == "table" then
		return value
	end
	return nil
end
function M.setup()
	local overrides = get_highlight_overrides()
	for group_name, group_def in pairs(M.groups) do
		local user_override = normalize_override(overrides[group_name])
		local def = group_def
		if user_override then
			def = vim.tbl_deep_extend("force", {}, group_def, user_override)
		end

		if group_name == "XmapCursor" and def.link then
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
function M.apply(bufnr, ns_id, hl_group, line, col_start, col_end)
	pcall(vim.api.nvim_buf_add_highlight, bufnr, ns_id, hl_group, line, col_start, col_end)
end
function M.clear(bufnr, ns_id, line_start, line_end)
	line_start = line_start or 0
	line_end = line_end or -1
	pcall(vim.api.nvim_buf_clear_namespace, bufnr, ns_id, line_start, line_end)
end
function M.create_namespace(name)
	return vim.api.nvim_create_namespace("xmap_" .. name)
end
function M.refresh()
	M.setup()
end

return M
