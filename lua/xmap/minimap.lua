-- lua/xmap/minimap.lua
-- Minimap window and rendering logic for xmap.nvim
--
-- This is the core runtime module of the plugin. It owns:
--   - the minimap scratch buffer + split window
--   - render/update loops (throttled, cursor-only updates)
--   - mapping between minimap lines and source buffer lines
--   - applying multiple highlight layers (viewport, cursor, prefix, structure)
--
-- Important separation of concerns:
--   - Language-specific parsing lives in provider modules (`lua/xmap/lang/<filetype>.lua`)
--   - Keyword filtering rules live in `symbols.lua`
--   - Tree-sitter queries + node extraction live in `treesitter.lua`
--   - Highlight group definitions/overrides live in `highlight.lua`
--
-- The minimap is a *derived view*: it does not necessarily include every source line.
-- When a line *is* rendered, we record a mapping:
--   minimap_line (1-indexed) -> source_line (1-indexed)
-- This mapping is used by navigation/jump logic.

local config = require("xmap.config")
local highlight = require("xmap.highlight")
local lang = require("xmap.lang")
local symbols = require("xmap.symbols")
local treesitter = require("xmap.treesitter")
local navigation = require("xmap.navigation")

local M = {}

-- The relative distance column is capped to keep layout stable.
local MAX_RELATIVE_DISTANCE = 999

local function pad_right(text, width)
	-- Pad using display width so multi-byte symbols (e.g. "↓", "·") don't produce
	-- unexpected extra spaces. This keeps the prefix visually aligned.
	text = text or ""
	local len = vim.api.nvim_strwidth(text)
	if len >= width then
		return text
	end
	return text .. string.rep(" ", width - len)
end

local function build_relative_prefix_settings(opts)
	-- Normalize the `render.relative_prefix` config into a compact table the render loop
	-- can reuse. This is called once per full render and cached in `M.state`.
	local render_opts = (opts and opts.render) or {}
	local rp = type(render_opts.relative_prefix) == "table" and render_opts.relative_prefix or {}

	local number_width = tonumber(rp.number_width) or 3
	if number_width < 1 then
		number_width = 1
	end

	local number_separator = type(rp.number_separator) == "string" and rp.number_separator or " "
	local separator = type(rp.separator) == "string" and rp.separator or " "
	local dir = type(rp.direction) == "table" and rp.direction or {}

	local indicators = {
		up = type(dir.up) == "string" and dir.up or "↑",
		down = type(dir.down) == "string" and dir.down or "↓",
		current = type(dir.current) == "string" and dir.current or "·",
	}

	local indicator_width = math.max(
		vim.api.nvim_strwidth(indicators.up),
		vim.api.nvim_strwidth(indicators.down),
		vim.api.nvim_strwidth(indicators.current)
	)

	return {
		number_width = number_width,
		number_separator = number_separator,
		separator = separator,
		indicators = indicators,
		indicator_width = indicator_width,
	}
end

local function format_relative_prefix(source_line, current_line, settings)
	-- Produce the prefix shown at the start of each minimap line, e.g.:
	--   " 12 ↓ " (distance + direction + trailing separator)
	-- The prefix is re-rendered frequently (cursor moves), so keep it cheap.
	local delta = source_line - current_line
	local direction = "current"
	if delta < 0 then
		direction = "up"
	elseif delta > 0 then
		direction = "down"
	end

	local distance = math.abs(delta)
	if distance > MAX_RELATIVE_DISTANCE then
		distance = MAX_RELATIVE_DISTANCE
	end

	settings = settings or build_relative_prefix_settings(config.get())
	local indicator = settings.indicators[direction] or ""
	local prefix = string.format("%" .. settings.number_width .. "d", distance)
		.. (settings.number_separator or "")
		.. pad_right(indicator, settings.indicator_width)
		.. settings.separator

	return direction, prefix
end

-- Minimap state
M.state = {
	-- Window/buffer handles
	bufnr = nil, -- Minimap scratch buffer (render target)
	winid = nil, -- Minimap split window
	main_bufnr = nil, -- Source buffer currently being mapped
	main_winid = nil, -- Window showing the source buffer

	-- Lifecycle flags/timers
	is_open = false,
	last_update = 0, -- Last full render timestamp (ms)
	update_timer = nil, -- Throttle timer for full renders
	last_relative_update = 0, -- Last prefix-only update timestamp (ms)
	relative_timer = nil, -- Throttle timer for prefix-only updates

	-- Render caches
	line_mapping = {}, -- minimap_line -> source_line mapping (both 1-indexed)
	content_by_line = {}, -- minimap_line -> rendered content (without prefix)
	entry_kinds = {}, -- minimap_line -> entry kind ("symbol", "comment", etc.)
	entry_symbols = {}, -- minimap_line -> parsed symbol metadata (if any)
	structural_nodes = {}, -- Cached Tree-sitter nodes for structural highlighting
	relative_prefix_settings = nil, -- Cached prefix config (widths, symbols, separators)

	-- Navigation UX helpers
	navigation_anchor_line = nil, -- Base line for relative distances while minimap is focused
	follow_scheduled = false, -- Coalesce follow-current-buffer updates
}

local function get_relative_base_line(main_winid)
	-- While the minimap is focused we can optionally "anchor" the base line so the
	-- relative numbers don't constantly shift under the cursor during navigation.
	-- This makes the minimap feel more like a stable list.
	local current_line = navigation.get_main_cursor_line(main_winid)
	if not (M.state.navigation_anchor_line and M.state.winid and vim.api.nvim_win_is_valid(M.state.winid)) then
		return current_line
	end
	if vim.api.nvim_get_current_win() ~= M.state.winid then
		return current_line
	end
	return M.state.navigation_anchor_line
end

-- Namespace for highlights
-- We use separate namespaces so different highlight layers can be cleared independently:
--   - viewport: the portion visible in the main window
--   - cursor: the minimap cursor/selection row
--   - syntax: relative prefix + comment/keyword highlights
--   - structure: Tree-sitter structural highlights (function/class ranges)
M.ns_viewport = highlight.create_namespace("viewport")
M.ns_cursor = highlight.create_namespace("cursor")
M.ns_syntax = highlight.create_namespace("syntax") -- arrows, numbers, comments
M.ns_structure = highlight.create_namespace("structure") -- Tree-sitter structural scopes

-- Create minimap buffer
-- @return number: Buffer number
function M.create_buffer()
	local buf_name = "xmap://minimap"

	-- Check if a buffer with this name already exists
	-- (this can happen during hot-reload or when the plugin didn't clean up properly).
	local existing_buf = vim.fn.bufnr(buf_name)
	if existing_buf ~= -1 and vim.api.nvim_buf_is_valid(existing_buf) then
		-- Delete the existing buffer
		pcall(vim.api.nvim_buf_delete, existing_buf, { force = true })
	end

	local buf = vim.api.nvim_create_buf(false, true) -- No file, scratch buffer

	-- Set buffer options
	-- The minimap buffer is:
	--   - unlisted (doesn't show up in :ls)
	--   - wiped when hidden (so it won't linger)
	--   - marked as "xmap" filetype (useful for custom highlights if desired)
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(buf, "swapfile", false)
	vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(buf, "buflisted", false)
	vim.api.nvim_buf_set_option(buf, "filetype", "xmap")
	vim.api.nvim_buf_set_name(buf, buf_name)

	-- We toggle `modifiable` only while writing new lines during updates.
	-- Keep it `true` here so the first render can populate content.
	vim.api.nvim_buf_set_option(buf, "modifiable", true)

	return buf
end

-- Create minimap window
-- @param bufnr number: Buffer to display in minimap
-- @return number: Window ID
function M.create_window(bufnr)
	local opts = config.get()

	-- Create split window instead of floating for better integration.
	-- We keep the minimap as a standard split so it plays well with window navigation
	-- and doesn't require floating-window sizing logic.
	local current_win = vim.api.nvim_get_current_win()

	-- Create vertical split
	-- Use `botright`/`topleft` so the minimap stays pinned to the outer edge of the
	-- tabpage layout (instead of splitting relative to the currently-focused window).
	if opts.side == "left" then
		vim.cmd("topleft vsplit")
	else
		vim.cmd("botright vsplit")
	end

	local win = vim.api.nvim_get_current_win()

	-- Set the buffer in the new window
	vim.api.nvim_win_set_buf(win, bufnr)

	-- Set window width
	vim.api.nvim_win_set_width(win, opts.width)

	-- Set window options
	-- The minimap window is a "view only" panel: no line numbers, no wraps, no signs,
	-- and a fixed width so the layout stays stable while editing.
	vim.api.nvim_win_set_option(win, "number", false)
	vim.api.nvim_win_set_option(win, "relativenumber", false)
	vim.api.nvim_win_set_option(win, "cursorline", false)
	vim.api.nvim_win_set_option(win, "wrap", false)
	vim.api.nvim_win_set_option(win, "signcolumn", "no")
	vim.api.nvim_win_set_option(win, "foldcolumn", "0")
	vim.api.nvim_win_set_option(win, "winfixwidth", true)
	vim.api.nvim_win_set_option(win, "fillchars", "eob: ") -- Remove ~ for empty lines
	vim.api.nvim_win_set_option(
		win,
		"winhighlight",
		"Normal:XmapBackground,NormalNC:XmapBackground,EndOfBuffer:XmapBackground,SignColumn:XmapBackground,FoldColumn:XmapBackground"
	)

	-- Return to original window
	vim.api.nvim_set_current_win(current_win)

	return win
end

local COMMENT_ICON = treesitter.get_icon_for_type("comment")
local MARKDOWN_HEADING_HIGHLIGHTS = {
	H1 = "XmapMarkdownH1",
	H2 = "XmapMarkdownH2",
	H3 = "XmapMarkdownH3",
	H4 = "XmapMarkdownH4",
	H5 = "XmapMarkdownH5",
	H6 = "XmapMarkdownH6",
}

-- Render a single line for the minimap (language-driven structural overview)
-- @param line string: Original line from main buffer
-- @param line_nr number: Line number (1-indexed)
-- @param current_line number: Current base line in main buffer (1-indexed)
-- @param all_lines table: All buffer lines (for context)
-- @param ctx table: Rendering context (provider, enabled keywords, etc.)
-- @return string|nil, string|nil, string|nil: Rendered line, content, and entry kind (or nil)
function M.render_line(line, line_nr, current_line, all_lines, ctx)
	-- The minimap does not render every source line. A provider decides:
	--   - which comment lines are worth showing (including MARK/TODO markers)
	--   - which declarations count as a "symbol" entry (func/struct/enum/etc.)
	--
	-- We return both:
	--   1) the full rendered line (prefix + content)
	--   2) the content portion only (used for fast prefix-only updates)
	--   3) the entry kind (used for comment/symbol highlighting decisions)
	if not ctx or not ctx.provider then
		return nil
	end

	local trimmed = vim.trim(line)
	local content = nil
	local entry_kind = nil
	local entry_symbol = nil

	if trimmed ~= "" and ctx.provider.is_comment_line and ctx.provider.is_comment_line(trimmed) then
		-- Comments/markers are rendered as separate minimap entries with the comment icon.
		if type(ctx.provider.render_comment) ~= "function" then
			return nil
		end
		local entry = ctx.provider.render_comment(line, line_nr, all_lines)
		if not entry then
			return nil
		end

		if entry.kind == "marker" then
			entry_kind = "marker"
			content = "⚑ " .. entry.marker .. ": " .. (entry.text or "")
		else
			local comment_symbol = nil
			if entry.kind == "commented_symbol" and entry.symbol then
				comment_symbol = entry.symbol
			elseif type(ctx.provider.extract_comment) == "function" and type(ctx.provider.parse_symbol) == "function" then
				local _, _, _, raw_text = ctx.provider.extract_comment(line)
				if raw_text and raw_text ~= "" then
					comment_symbol = ctx.provider.parse_symbol(raw_text)
				end
			end

			if comment_symbol and ctx.enabled_symbol_keywords and ctx.enabled_symbol_keywords[comment_symbol.keyword] then
				local icon = treesitter.get_icon_for_type(comment_symbol.capture_type)
				local compact = tostring(comment_symbol.display or ""):gsub("%s+", " ")
				local max_len = (ctx.opts.render and ctx.opts.render.max_line_length) or 40
				if #compact > max_len then
					compact = compact:sub(1, max_len - 3) .. "..."
				end
				entry_kind = "commented_symbol"
				content = COMMENT_ICON .. " " .. icon .. " " .. compact
			else
				entry_kind = "comment"
				content = COMMENT_ICON .. " " .. (entry.text or "")
			end
		end
	elseif type(ctx.provider.parse_symbol) == "function" then
		-- Symbols are identified by a cheap line parser that extracts the declaration kind and name.
		local symbol = ctx.provider.parse_symbol(trimmed, line_nr, all_lines)
		if not symbol then
			return nil
		end

		-- Apply per-language keyword filtering (configured via `opts.symbols.<filetype>`).
		if not (ctx.enabled_symbol_keywords and ctx.enabled_symbol_keywords[symbol.keyword]) then
			return nil
		end

		local icon = symbol.icon or treesitter.get_icon_for_type(symbol.capture_type)
		local compact = tostring(symbol.display or ""):gsub("%s+", " ")
		local max_len = (ctx.opts.render and ctx.opts.render.max_line_length) or 40
		if #compact > max_len then
			compact = compact:sub(1, max_len - 3) .. "..."
		end

		entry_kind = "symbol"
		if icon and icon ~= "" then
			content = icon .. " " .. compact
		else
			content = compact
		end
		entry_symbol = symbol
	else
		return nil
	end

	if not content then
		return nil
	end

	local _, prefix = format_relative_prefix(line_nr, current_line, ctx.prefix_settings)
	return prefix .. content, content, entry_kind, entry_symbol
end

-- Render entire buffer content for minimap
-- @param main_bufnr number: Main buffer to render
-- @param main_winid number: Main window (to get current line)
-- @param current_line_override number|nil: Optional base line override
-- @return string[], integer[], table, table, string[], string[]:
--   rendered_lines, line_mapping, structural_nodes, prefix_settings, content_by_line, entry_kinds, entry_symbols
function M.render_buffer(main_bufnr, main_winid, current_line_override)
	if not vim.api.nvim_buf_is_valid(main_bufnr) then
		return {}, {}, {}, {}, {}, {}
	end

	local opts = config.get()
	local prefix_settings = build_relative_prefix_settings(opts)

	-- Get current line in main buffer
	local current_line = current_line_override or navigation.get_main_cursor_line(main_winid)

	local lines = vim.api.nvim_buf_get_lines(main_bufnr, 0, -1, false)
	local rendered = {}
	local content_by_line = {}
	local entry_kinds = {}
	local entry_symbols = {}
	local line_mapping = {} -- Maps minimap line number to source line number
	local structural_nodes = {}

	-- Identify which language provider to use (based on `vim.bo.filetype`).
	-- If no provider exists, xmap does not render anything for this buffer.
	local filetype = vim.api.nvim_buf_get_option(main_bufnr, "filetype")
	local provider = lang.get(filetype)
	if not provider then
		return {}, {}, {}, {}, {}, {}, {}
	end

	-- Tree-sitter is optional and used only for structural highlighting.
	-- The minimap list itself is rendered using the provider's line parser.
	if config.is_treesitter_enabled(filetype) then
		structural_nodes = treesitter.get_structural_nodes(main_bufnr, filetype)
	end

	-- Build the enabled keyword set once and reuse it for every line.
	local enabled_symbol_keywords = symbols.get_enabled_keyword_set(
		opts,
		filetype,
		provider.default_symbol_keywords or {}
	) or {}

	local ctx = {
		opts = opts,
		provider = provider,
		enabled_symbol_keywords = enabled_symbol_keywords,
		prefix_settings = prefix_settings,
	}

	for i, line in ipairs(lines) do
		local rendered_line, content, entry_kind, entry_symbol = M.render_line(line, i, current_line, lines, ctx)
		if rendered_line then
			table.insert(rendered, rendered_line)
			table.insert(content_by_line, content or "")
			table.insert(entry_kinds, entry_kind or "symbol")
			table.insert(entry_symbols, entry_symbol)
			table.insert(line_mapping, i) -- Store source line number
		end
	end

	return rendered, line_mapping, structural_nodes, prefix_settings, content_by_line, entry_kinds, entry_symbols
end

-- Apply highlighting for relative numbers, arrows, icons, and comments
-- @param minimap_bufnr number: Minimap buffer
-- @param main_bufnr number: Main buffer
-- @param main_winid number: Main window
-- @param current_line_override number|nil: Optional base line override
function M.apply_relative_number_highlighting(minimap_bufnr, main_bufnr, main_winid, current_line_override)
	-- This highlight pass covers the "syntax layer" of the minimap:
	--   - relative distance number (XmapRelativeNumber)
	--   - direction indicator (XmapRelativeUp/Down/Current)
	--   - comment markers (MARK/TODO/FIXME/...)
	--   - comment lines (doc vs normal)
	--   - keyword + entity name highlighting for symbol lines
	--
	-- It intentionally does not touch:
	--   - viewport background (ns_viewport)
	--   - minimap cursor line background (ns_cursor)
	--   - structural scope highlights (ns_structure)
	if not vim.api.nvim_buf_is_valid(minimap_bufnr) or not vim.api.nvim_buf_is_valid(main_bufnr) then
		return
	end

	local opts = config.get()
	local prefix_settings = M.state.relative_prefix_settings or build_relative_prefix_settings(opts)

	-- Prefix layout is:
	--   [number_width chars][number_separator][indicator (padded)][separator]
	--
	-- NOTE: highlight column indices are byte offsets. We compute lengths using `#`
	-- on the final prefix fragments to match Neovim's API expectations.
	local number_width = prefix_settings.number_width or 3
	local number_sep_len = #(prefix_settings.number_separator or "")
	local number_end = number_width + number_sep_len
	local indicator_start = number_end
	local indicator_width = prefix_settings.indicator_width or 0
	local indicator_fields = {
		up = pad_right((prefix_settings.indicators and prefix_settings.indicators.up) or "↑", indicator_width),
		down = pad_right((prefix_settings.indicators and prefix_settings.indicators.down) or "↓", indicator_width),
		current = pad_right((prefix_settings.indicators and prefix_settings.indicators.current) or "·", indicator_width),
	}
	local indicator_field_lens = {
		up = #indicator_fields.up,
		down = #indicator_fields.down,
		current = #indicator_fields.current,
	}

	local filetype = vim.api.nvim_buf_get_option(main_bufnr, "filetype")
	local provider = lang.get(filetype)
	local highlight_keywords = {}
	if provider then
		highlight_keywords = symbols.get_highlight_keywords(
			opts,
			filetype,
			provider.default_highlight_keywords or provider.default_symbol_keywords or {}
		) or {}
	end

	-- Clear previous highlights
	highlight.clear(minimap_bufnr, M.ns_syntax)

	-- Get current line
	local current_line = current_line_override or navigation.get_main_cursor_line(main_winid)

	-- Get minimap lines
	local minimap_lines = vim.api.nvim_buf_get_lines(minimap_bufnr, 0, -1, false)

	-- Highlight each line
	for minimap_line_nr = 1, #minimap_lines do
		local line_text = minimap_lines[minimap_line_nr]

		-- Get actual source line number from mapping
		local source_line_nr = M.state.line_mapping[minimap_line_nr]
		if not source_line_nr then
			goto continue
		end
		local entry_kind = M.state.entry_kinds and M.state.entry_kinds[minimap_line_nr]

		local delta = source_line_nr - current_line

		-- Highlight number portion
		highlight.apply(minimap_bufnr, M.ns_syntax, "XmapRelativeNumber", minimap_line_nr - 1, 0, number_end)

		-- Highlight direction indicator portion
		local direction = "current"
		local hl_group = "XmapRelativeCurrent"
		if delta < 0 then
			direction = "up"
			hl_group = "XmapRelativeUp"
		elseif delta > 0 then
			direction = "down"
			hl_group = "XmapRelativeDown"
		end

		local indicator_end = indicator_start + (indicator_field_lens[direction] or 0)
		highlight.apply(minimap_bufnr, M.ns_syntax, hl_group, minimap_line_nr - 1, indicator_start, indicator_end)

		-- Check for special comment markers (highlight the entire marker line for visibility)
		if line_text:match("⚑ MARK:") then
			local icon_pos = line_text:find("⚑")
			if icon_pos then
				highlight.apply(
					minimap_bufnr,
					M.ns_syntax,
					"XmapCommentMark",
					minimap_line_nr - 1,
					icon_pos - 1,
					-1
				)
			end
		elseif line_text:match("⚑ TODO:") then
			local icon_pos = line_text:find("⚑")
			if icon_pos then
				highlight.apply(
					minimap_bufnr,
					M.ns_syntax,
					"XmapCommentTodo",
					minimap_line_nr - 1,
					icon_pos - 1,
					-1
				)
			end
		elseif line_text:match("⚑ FIXME:") then
			local icon_pos = line_text:find("⚑")
			if icon_pos then
				highlight.apply(
					minimap_bufnr,
					M.ns_syntax,
					"XmapCommentFixme",
					minimap_line_nr - 1,
					icon_pos - 1,
					-1
				)
			end
		elseif line_text:match("⚑ NOTE:") then
			local icon_pos = line_text:find("⚑")
			if icon_pos then
				highlight.apply(
					minimap_bufnr,
					M.ns_syntax,
					"XmapCommentNote",
					minimap_line_nr - 1,
					icon_pos - 1,
					-1
				)
			end
		elseif line_text:match("⚑ WARNING:") then
			local icon_pos = line_text:find("⚑")
			if icon_pos then
				highlight.apply(
					minimap_bufnr,
					M.ns_syntax,
					"XmapCommentWarning",
					minimap_line_nr - 1,
					icon_pos - 1,
					-1
				)
			end
		elseif line_text:match("⚑ BUG:") then
			local icon_pos = line_text:find("⚑")
			if icon_pos then
				highlight.apply(
					minimap_bufnr,
					M.ns_syntax,
					"XmapCommentBug",
					minimap_line_nr - 1,
					icon_pos - 1,
					-1
				)
			end
		else
			-- Rendered comment lines start with a comment icon; highlight accordingly.
			local comment_icon = COMMENT_ICON
			local comment_icon_pos = line_text:find(comment_icon, 1, true)
			if comment_icon_pos then
				local hl_group = "XmapCommentNormal"
				if provider and type(provider.extract_comment) == "function" then
					local source_line = vim.api.nvim_buf_get_lines(
						main_bufnr,
						source_line_nr - 1,
						source_line_nr,
						false
					)[1] or ""
					local _, _, is_doc_comment = provider.extract_comment(source_line)
					if is_doc_comment then
						hl_group = "XmapCommentDoc"
					end
				end

				if entry_kind == "commented_symbol" then
					local icon_end = comment_icon_pos - 1 + #comment_icon
					highlight.apply(minimap_bufnr, M.ns_syntax, hl_group, minimap_line_nr - 1, comment_icon_pos - 1, icon_end)
				else
					highlight.apply(minimap_bufnr, M.ns_syntax, hl_group, minimap_line_nr - 1, comment_icon_pos - 1, -1)
					goto continue
				end
			end

			local entry_symbol = M.state.entry_symbols and M.state.entry_symbols[minimap_line_nr]
			if filetype == "markdown" and entry_symbol and entry_symbol.keyword then
				local heading_hl = MARKDOWN_HEADING_HIGHLIGHTS[entry_symbol.keyword]
				if heading_hl then
					local _, prefix = format_relative_prefix(source_line_nr, current_line, prefix_settings)
					local icon = entry_symbol.icon or ""
					local text_start = #prefix
					if icon ~= "" then
						local icon_end = #prefix + #icon
						highlight.apply(minimap_bufnr, M.ns_syntax, heading_hl, minimap_line_nr - 1, #prefix, icon_end)
						text_start = icon_end
						if line_text:sub(icon_end + 1, icon_end + 1) == " " then
							text_start = icon_end + 1
						end
					end
					if text_start < #line_text then
						highlight.apply(
							minimap_bufnr,
							M.ns_syntax,
							"XmapMarkdownHeadingText",
							minimap_line_nr - 1,
							text_start,
							-1
						)
					end
					goto continue
				end
			end

			-- Try to highlight keywords on ALL lines, not just structural nodes
			-- Text format: " 22↓ 󰊕 func init"
			-- Skip prefix and icons, then find the first letter
			local _, text_start = line_text:find("^[^%a]*") -- Skip everything that's not a letter
			text_start = text_start and text_start + 1 -- Position after non-letters

			if text_start and text_start <= #line_text then
				local text_after_numbers = line_text:sub(text_start)

				for _, keyword in ipairs(highlight_keywords) do
					local kw_start, kw_end = text_after_numbers:find("^" .. keyword)
					if kw_start then
						local next_char = text_after_numbers:sub(kw_end + 1, kw_end + 1)
						if next_char ~= "" and next_char:match("[%w_]") then
							goto continue_keyword
						end

						-- Found keyword at start of text
						local kw_pos_in_line = text_start - 1 + kw_start - 1 -- Position in full line (0-indexed)
						local kw_end_pos_in_line = text_start - 1 + kw_end

						local keyword_hl = "XmapRelativeKeyword"
						local entity_hl = "XmapRelativeEntity"
						if filetype == "markdown" then
							local heading_hl = MARKDOWN_HEADING_HIGHLIGHTS[keyword]
							if heading_hl then
								keyword_hl = heading_hl
								entity_hl = heading_hl
							end
						end

						-- Highlight keyword with colorscheme color
						highlight.apply(
							minimap_bufnr,
							M.ns_syntax,
							keyword_hl,
							minimap_line_nr - 1,
							kw_pos_in_line,
							kw_end_pos_in_line
						)

						-- Highlight entity name after keyword (starting right after the space)
						local entity_start = kw_end_pos_in_line
						if entity_start < #line_text then
							highlight.apply(
								minimap_bufnr,
								M.ns_syntax,
								entity_hl,
								minimap_line_nr - 1,
								entity_start,
								-1
							)
						end
						break
					end
					::continue_keyword::
				end
			end
		end
		::continue::
	end
end

-- Apply syntax highlighting based on Tree-sitter
-- @param minimap_bufnr number: Minimap buffer
-- @param main_bufnr number: Main buffer
-- @param structural_nodes table|nil: Optional cached nodes
-- @param current_line_override number|nil: Optional base line override
-- @param prefix_settings_override table|nil: Optional cached prefix settings
function M.apply_syntax_highlighting(minimap_bufnr, main_bufnr, structural_nodes, current_line_override, prefix_settings_override)
	-- Structural highlighting uses Tree-sitter nodes from `treesitter.get_structural_nodes`.
	-- We only apply these highlights to lines that are actually rendered in the minimap.
	--
	-- Why compute the prefix length per line?
	-- Prefix width can vary when users provide multi-byte direction indicators or
	-- different separators. Instead of relying on a cached constant, we compute the
	-- exact prefix string for the line and highlight from `#prefix` onward.
	if not vim.api.nvim_buf_is_valid(minimap_bufnr) or not vim.api.nvim_buf_is_valid(main_bufnr) then
		return
	end

	local opts = config.get()
	local filetype = vim.api.nvim_buf_get_option(main_bufnr, "filetype")

	if not opts.treesitter.highlight_scopes or not config.is_treesitter_enabled(filetype) then
		return
	end

	local current_line = current_line_override
	if not current_line then
		if M.state.main_winid and vim.api.nvim_win_is_valid(M.state.main_winid) then
			current_line = get_relative_base_line(M.state.main_winid)
		else
			current_line = 1
		end
	end

	local prefix_settings = prefix_settings_override
		or M.state.relative_prefix_settings
		or build_relative_prefix_settings(opts)

	-- Clear previous structural highlights without touching relative/arrow highlights
	highlight.clear(minimap_bufnr, M.ns_structure)

	-- Build a reverse lookup: source line -> minimap line
	local line_lookup = {}
	for minimap_line, source_line in ipairs(M.state.line_mapping or {}) do
		line_lookup[source_line] = minimap_line
	end

	-- Get structural nodes from Tree-sitter
	local nodes = structural_nodes or treesitter.get_structural_nodes(main_bufnr, filetype)

	-- Apply highlights for each structural node (only if rendered in minimap)
	for _, node in ipairs(nodes) do
		local hl_group = treesitter.get_highlight_for_type(node.type)

		-- Minimaps render only key structural lines, so highlight the start line if present
		local source_line = node.start_line + 1 -- convert to 1-indexed
		local minimap_line = line_lookup[source_line]
		if minimap_line then
			if filetype == "markdown" then
				local entry_symbol = M.state.entry_symbols and M.state.entry_symbols[minimap_line]
				if entry_symbol and entry_symbol.keyword and entry_symbol.keyword:match("^H[1-6]$") then
					goto continue_node
				end
			end
			local _, prefix = format_relative_prefix(source_line, current_line, prefix_settings)
			highlight.apply(minimap_bufnr, M.ns_structure, hl_group, minimap_line - 1, #prefix, -1)
		end
		::continue_node::
	end
end

function M.highlight_cursor_line(minimap_bufnr, minimap_line)
	if not vim.api.nvim_buf_is_valid(minimap_bufnr) then
		return
	end

	highlight.clear(minimap_bufnr, M.ns_cursor)

	if not minimap_line or minimap_line < 1 then
		return
	end

	-- Use an extmark with `hl_eol` so the highlight covers the full window width.
	pcall(vim.api.nvim_buf_set_extmark, minimap_bufnr, M.ns_cursor, minimap_line - 1, 0, {
		hl_group = "XmapCursor",
		hl_eol = true,
		hl_mode = "combine",
		priority = 100,
	})
end

-- Update only the relative prefix + highlighting for cursor moves.
function M.update_relative_only()
	-- CursorMoved events happen frequently. A full render re-parses the whole buffer,
	-- so for performance we keep a "prefix-only" path:
	--   - reuse previously rendered content (icons + text) from `M.state.content_by_line`
	--   - re-render only the relative prefix for each minimap line
	--   - re-apply highlights that depend on prefix positions
	if not M.state.is_open or not M.state.bufnr or not M.state.main_bufnr then
		return
	end

	if not vim.api.nvim_buf_is_valid(M.state.bufnr) or not vim.api.nvim_buf_is_valid(M.state.main_bufnr) then
		M.close()
		return
	end

	if not (M.state.main_winid and vim.api.nvim_win_is_valid(M.state.main_winid)) then
		return
	end

	local current_line = get_relative_base_line(M.state.main_winid)
	local prefix_settings = M.state.relative_prefix_settings or build_relative_prefix_settings(config.get())
	local existing_lines = vim.api.nvim_buf_get_lines(M.state.bufnr, 0, -1, false)

	local updated = {}
	local changed = false
	local content_by_line = M.state.content_by_line or {}

	for minimap_line, line_text in ipairs(existing_lines) do
		local source_line = M.state.line_mapping[minimap_line]
		local content = content_by_line[minimap_line]
		if source_line and type(content) == "string" then
			local _, prefix = format_relative_prefix(source_line, current_line, prefix_settings)
			local new_text = prefix .. content
			updated[minimap_line] = new_text
			if new_text ~= line_text then
				changed = true
			end
		else
			updated[minimap_line] = line_text
		end
	end

	if changed then
		vim.api.nvim_buf_set_option(M.state.bufnr, "modifiable", true)
		vim.api.nvim_buf_set_lines(M.state.bufnr, 0, -1, false, updated)
		vim.api.nvim_buf_set_option(M.state.bufnr, "modifiable", false)
	end

	-- Clear background-style highlights (viewport/cursor) and refresh syntax highlights.
	highlight.clear(M.state.bufnr, M.ns_viewport)
	highlight.clear(M.state.bufnr, M.ns_cursor)
	-- Structural highlights are re-applied too because they start *after* the prefix.
	M.apply_syntax_highlighting(M.state.bufnr, M.state.main_bufnr, M.state.structural_nodes, current_line, prefix_settings)
	M.apply_relative_number_highlighting(M.state.bufnr, M.state.main_bufnr, M.state.main_winid, current_line)

	if M.state.winid and vim.api.nvim_win_is_valid(M.state.winid) then
		local is_minimap_focused = vim.api.nvim_get_current_win() == M.state.winid
		if not is_minimap_focused then
			navigation.update_minimap_cursor(M.state.winid, current_line, M.state.line_mapping)
		end
		local minimap_line = vim.api.nvim_win_get_cursor(M.state.winid)[1]
		M.highlight_cursor_line(M.state.bufnr, minimap_line)
	end

	M.state.last_relative_update = vim.loop.now()
end

function M.throttled_relative_update()
	-- Debounce prefix-only updates to avoid spamming work during rapid cursor motion.
	local opts = config.get()
	local now = vim.loop.now()

	if now - (M.state.last_relative_update or 0) < (opts.render.throttle_ms or 0) then
		if M.state.relative_timer then
			M.state.relative_timer:stop()
		end
		M.state.relative_timer = vim.defer_fn(function()
			M.update_relative_only()
		end, opts.render.throttle_ms)
		return
	end

	M.update_relative_only()
end

-- Update minimap content
function M.update()
	-- Full render path:
	--   - re-scan buffer lines
	--   - re-run provider parsing and keyword filtering
	--   - refresh structural nodes (Tree-sitter) if enabled
	--   - update the minimap buffer lines + caches
	if not M.state.is_open or not M.state.bufnr or not M.state.main_bufnr then
		return
	end

	if not vim.api.nvim_buf_is_valid(M.state.bufnr) or not vim.api.nvim_buf_is_valid(M.state.main_bufnr) then
		M.close()
		return
	end

	-- Render buffer content with relative line numbers
	local current_line = get_relative_base_line(M.state.main_winid)
	local rendered_lines, line_mapping, structural_nodes, prefix_settings, content_by_line, entry_kinds, entry_symbols =
		M.render_buffer(M.state.main_bufnr, M.state.main_winid, current_line)

	-- Store line mapping for navigation
	M.state.line_mapping = line_mapping
	M.state.content_by_line = content_by_line or {}
	M.state.entry_kinds = entry_kinds or {}
	M.state.entry_symbols = entry_symbols or {}
	M.state.structural_nodes = structural_nodes or {}
	if prefix_settings then
		M.state.relative_prefix_settings = prefix_settings
	end

	-- Update minimap buffer
	vim.api.nvim_buf_set_option(M.state.bufnr, "modifiable", true)
	vim.api.nvim_buf_set_lines(M.state.bufnr, 0, -1, false, rendered_lines)
	vim.api.nvim_buf_set_option(M.state.bufnr, "modifiable", false)

	-- Apply syntax highlighting for arrows, numbers, icons, and structure
	highlight.clear(M.state.bufnr, M.ns_viewport)
	highlight.clear(M.state.bufnr, M.ns_cursor)
	M.apply_syntax_highlighting(M.state.bufnr, M.state.main_bufnr, structural_nodes, current_line, prefix_settings)
	M.apply_relative_number_highlighting(M.state.bufnr, M.state.main_bufnr, M.state.main_winid, current_line)

	-- Update minimap cursor to follow main buffer
	if M.state.main_winid and vim.api.nvim_win_is_valid(M.state.main_winid) then
		local main_line = navigation.get_main_cursor_line(M.state.main_winid)
		if M.state.winid and vim.api.nvim_win_is_valid(M.state.winid) then
			local is_minimap_focused = vim.api.nvim_get_current_win() == M.state.winid
			if not is_minimap_focused then
				navigation.update_minimap_cursor(M.state.winid, main_line, M.state.line_mapping)
			end
			local minimap_line = vim.api.nvim_win_get_cursor(M.state.winid)[1]
			M.highlight_cursor_line(M.state.bufnr, minimap_line)
		end
	end

	M.state.last_update = vim.loop.now()
end

-- Throttled update function
function M.throttled_update()
	-- Debounce full renders to avoid doing heavy work on every keystroke.
	-- The throttle interval is shared with prefix-only updates for consistency.
	local opts = config.get()
	local now = vim.loop.now()

	-- Check if enough time has passed since last update
	if now - M.state.last_update < opts.render.throttle_ms then
		-- Schedule update for later
		if M.state.update_timer then
			M.state.update_timer:stop()
		end

		M.state.update_timer = vim.defer_fn(function()
			M.update()
		end, opts.render.throttle_ms)

		return
	end

	M.update()
end

-- Follow the currently active window/buffer when minimap is open.
-- This keeps the minimap in sync when switching buffers or windows.
function M._follow_current_target()
	-- This function implements "follow active buffer" semantics:
	--   1) If the currently focused window/buffer is a supported target, attach to it.
	--   2) Else, if the previously attached target still exists, try to find a window showing it.
	--   3) Else, scan all windows for the first supported target.
	--   4) If no supported buffers remain, close the minimap.
	if not M.state.is_open then
		return
	end
	if not (M.state.winid and vim.api.nvim_win_is_valid(M.state.winid)) then
		M.close()
		return
	end

	local function is_supported_target(bufnr)
		if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
			return false
		end
		if M.state.bufnr and bufnr == M.state.bufnr then
			return false
		end
		local buftype = vim.api.nvim_buf_get_option(bufnr, "buftype")
		if buftype ~= "" then
			return false
		end
		local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")
		return config.is_filetype_supported(filetype)
	end

	local function attach_target(main_bufnr, main_winid)
		-- Switching targets requires updating autocmds (buffer-local) and re-rendering.
		local buffer_changed = main_bufnr ~= M.state.main_bufnr
		local win_changed = main_winid ~= M.state.main_winid

		if not buffer_changed and not win_changed then
			return
		end

		M.state.main_bufnr = main_bufnr
		M.state.main_winid = main_winid
		M.state.navigation_anchor_line = nil

		if buffer_changed then
			M.setup_autocommands()
			M.update()
		else
			M.throttled_relative_update()
		end
	end

	local current_winid = vim.api.nvim_get_current_win()
	local current_bufnr = vim.api.nvim_get_current_buf()

	local current_is_minimap = current_winid == M.state.winid or current_bufnr == M.state.bufnr

	if not current_is_minimap and is_supported_target(current_bufnr) then
		attach_target(current_bufnr, current_winid)
		return
	end

	if is_supported_target(M.state.main_bufnr) then
		local main_winid = M.state.main_winid
		if
			not (
				main_winid
				and vim.api.nvim_win_is_valid(main_winid)
				and vim.api.nvim_win_get_buf(main_winid) == M.state.main_bufnr
			)
		then
			main_winid = nil
			for _, winid in ipairs(vim.api.nvim_list_wins()) do
				if winid ~= M.state.winid and vim.api.nvim_win_get_buf(winid) == M.state.main_bufnr then
					main_winid = winid
					break
				end
			end
		end

		if main_winid then
			attach_target(M.state.main_bufnr, main_winid)
			return
		end
	end

	for _, winid in ipairs(vim.api.nvim_list_wins()) do
		if winid ~= M.state.winid then
			local bufnr = vim.api.nvim_win_get_buf(winid)
			if is_supported_target(bufnr) then
				attach_target(bufnr, winid)
				return
			end
		end
	end

	M.close()
end

function M.follow_current_target()
	-- Coalesce multiple follow requests into a single scheduled callback.
	-- This avoids "double renders" when multiple autocmds fire in a row.
	if M.state.follow_scheduled then
		return
	end
	M.state.follow_scheduled = true
	vim.schedule(function()
		M.state.follow_scheduled = false
		M._follow_current_target()
	end)
end

-- Open minimap for current buffer
function M.open()
	-- Creates the minimap buffer + window and attaches to the currently active buffer.
	-- All further following/switching is handled by follow_current_target/autocmds.
	-- Check if already open
	if M.state.is_open and M.state.winid and vim.api.nvim_win_is_valid(M.state.winid) then
		return
	end

	-- Get current buffer and window
	local main_bufnr = vim.api.nvim_get_current_buf()
	local main_winid = vim.api.nvim_get_current_win()

	-- Check if filetype is supported
	local filetype = vim.api.nvim_buf_get_option(main_bufnr, "filetype")
	if not config.is_filetype_supported(filetype) then
		vim.notify("Minimap not supported for filetype: " .. filetype, vim.log.levels.INFO)
		return
	end

	-- Create buffer and window
	local bufnr = M.create_buffer()
	local winid = M.create_window(bufnr)

	-- Store state
	M.state.bufnr = bufnr
	M.state.winid = winid
	M.state.main_bufnr = main_bufnr
	M.state.main_winid = main_winid
	M.state.is_open = true

	-- Set up keymaps for minimap
	navigation.setup_minimap_keymaps(bufnr, winid, main_bufnr, main_winid)

	-- Initial render
	M.update()

	-- Set up autocommands for updating minimap
	M.setup_autocommands()
end

-- Close minimap
function M.close()
	-- Stops timers, removes autocmds, closes the minimap window, deletes the buffer,
	-- and resets state so a future open starts clean.
	if not M.state.is_open then
		return
	end

	local minimap_bufnr = M.state.bufnr
	local minimap_winid = M.state.winid

	-- Clear timers
	if M.state.update_timer then
		M.state.update_timer:stop()
		M.state.update_timer = nil
	end
	if M.state.relative_timer then
		M.state.relative_timer:stop()
		M.state.relative_timer = nil
	end

	-- Clear autocommands
	pcall(vim.api.nvim_del_augroup_by_name, "XmapUpdate")

	-- Close window (or repurpose it if it's the last window in the tabpage)
	-- When the minimap is the only window left in a tabpage, closing it would close the
	-- entire tab/window. Instead, we "repurpose" it by showing some other buffer.
	if minimap_winid and vim.api.nvim_win_is_valid(minimap_winid) then
		local tabpage = vim.api.nvim_win_get_tabpage(minimap_winid)
		local wins = vim.api.nvim_tabpage_list_wins(tabpage)

		if #wins > 1 then
			pcall(vim.api.nvim_win_close, minimap_winid, true)
		else
			local replacement_bufnr = nil

			if
				M.state.main_bufnr
				and vim.api.nvim_buf_is_valid(M.state.main_bufnr)
				and M.state.main_bufnr ~= minimap_bufnr
			then
				replacement_bufnr = M.state.main_bufnr
			end

			if not replacement_bufnr then
				for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
					if bufnr ~= minimap_bufnr and vim.api.nvim_buf_is_valid(bufnr) then
						local buftype = vim.api.nvim_buf_get_option(bufnr, "buftype")
						local listed = vim.api.nvim_buf_get_option(bufnr, "buflisted")
						if buftype == "" and listed then
							replacement_bufnr = bufnr
							break
						end
					end
				end
			end

			if replacement_bufnr then
				pcall(vim.api.nvim_win_set_buf, minimap_winid, replacement_bufnr)
			else
				pcall(vim.api.nvim_win_call, minimap_winid, function()
					vim.cmd("enew")
				end)
			end
		end
	end

	-- Delete buffer
	if minimap_bufnr and vim.api.nvim_buf_is_valid(minimap_bufnr) then
		pcall(vim.api.nvim_buf_delete, minimap_bufnr, { force = true })
	end

	-- Reset state
	M.state.bufnr = nil
	M.state.winid = nil
	M.state.main_bufnr = nil
	M.state.main_winid = nil
	M.state.is_open = false
	M.state.line_mapping = {}
	M.state.content_by_line = {}
	M.state.entry_kinds = {}
	M.state.entry_symbols = {}
	M.state.structural_nodes = {}
	M.state.relative_prefix_settings = nil
	M.state.navigation_anchor_line = nil
	M.state.follow_scheduled = false
end

-- Toggle minimap
function M.toggle()
	if M.state.is_open then
		M.close()
	else
		M.open()
	end
end

-- Set up autocommands for minimap updates
function M.setup_autocommands()
	-- Autocmds are buffer-local to the current main buffer and are recreated whenever
	-- the minimap attaches to a different buffer.
	local augroup = vim.api.nvim_create_augroup("XmapUpdate", { clear = true })

	-- Update on text changes
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = augroup,
		buffer = M.state.main_bufnr,
		callback = function()
			M.throttled_update()
		end,
	})

	-- Update on cursor movement
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = augroup,
		buffer = M.state.main_bufnr,
		callback = function()
			-- Use the fast prefix-only update if we already have a mapping.
			if
				M.state.bufnr
				and vim.api.nvim_buf_is_valid(M.state.bufnr)
				and M.state.line_mapping
				and #M.state.line_mapping > 0
			then
				M.throttled_relative_update()
				return
			end
			M.throttled_update()
		end,
	})

	-- Keep a cursor highlight inside the minimap:
	-- - while focused: follows minimap cursor (navigation)
	-- - while not focused: follows main cursor mapping
	vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
		group = augroup,
		buffer = M.state.bufnr,
		callback = function()
			if M.state.bufnr and M.state.winid and vim.api.nvim_win_is_valid(M.state.winid) then
				local opts = config.get()
				if
					opts.navigation.follow_cursor
					and M.state.main_winid
					and vim.api.nvim_win_is_valid(M.state.main_winid)
				then
					M.state.navigation_anchor_line = navigation.get_main_cursor_line(M.state.main_winid)
				else
					M.state.navigation_anchor_line = nil
				end
				local minimap_line = vim.api.nvim_win_get_cursor(M.state.winid)[1]
				M.highlight_cursor_line(M.state.bufnr, minimap_line)
			end
		end,
	})

	vim.api.nvim_create_autocmd("CursorMoved", {
		group = augroup,
		buffer = M.state.bufnr,
		callback = function()
			if M.state.bufnr and M.state.winid and vim.api.nvim_win_is_valid(M.state.winid) then
				local minimap_line = vim.api.nvim_win_get_cursor(M.state.winid)[1]
				M.highlight_cursor_line(M.state.bufnr, minimap_line)

				local opts = config.get()
				if opts.navigation.follow_cursor and vim.api.nvim_get_current_win() == M.state.winid then
					if M.state.main_bufnr and M.state.main_winid then
						navigation.center_main_on_minimap_cursor(
							M.state.winid,
							M.state.main_bufnr,
							M.state.main_winid,
							M.state.line_mapping
						)
					end
				end
			end
		end,
	})

	vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
		group = augroup,
		buffer = M.state.bufnr,
		callback = function()
			M.state.navigation_anchor_line = nil
			if not (M.state.bufnr and vim.api.nvim_buf_is_valid(M.state.bufnr)) then
				return
			end
			if not (M.state.winid and vim.api.nvim_win_is_valid(M.state.winid)) then
				return
			end
			if not (M.state.main_winid and vim.api.nvim_win_is_valid(M.state.main_winid)) then
				return
			end

			local main_line = navigation.get_main_cursor_line(M.state.main_winid)
			navigation.update_minimap_cursor(M.state.winid, main_line, M.state.line_mapping)
			local minimap_line = vim.api.nvim_win_get_cursor(M.state.winid)[1]
			M.highlight_cursor_line(M.state.bufnr, minimap_line)

			if M.state.main_bufnr and vim.api.nvim_buf_is_valid(M.state.main_bufnr) then
				M.update_relative_only()
			end
		end,
	})

	-- Update on buffer write
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = augroup,
		buffer = M.state.main_bufnr,
		callback = function()
			M.update()
		end,
	})

	-- Close minimap when main buffer is closed, deleted, or unloaded
	vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete", "BufUnload" }, {
		group = augroup,
		buffer = M.state.main_bufnr,
		callback = function()
			M.follow_current_target()
		end,
	})

	-- Keep minimap target in sync when switching buffers/windows.
	vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "FileType" }, {
		group = augroup,
		callback = function()
			if not M.state.is_open then
				return
			end

			M.follow_current_target()
		end,
	})

	-- Handle window resize
	vim.api.nvim_create_autocmd("VimResized", {
		group = augroup,
		callback = function()
			if M.state.is_open and M.state.winid and vim.api.nvim_win_is_valid(M.state.winid) then
				local opts = config.get()
				vim.api.nvim_win_set_width(M.state.winid, opts.width)
			end
		end,
	})
end

-- Check if minimap is open
-- @return boolean
function M.is_open()
	return M.state.is_open
end

return M
