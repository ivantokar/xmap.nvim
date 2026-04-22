-- PURPOSE:
-- - Own minimap buffer/window lifecycle, rendering, and follow-target state.
-- CONSTRAINTS:
-- - Keep parsing/provider logic outside this module.
-- - Treat the minimap as a derived view backed by `line_mapping`.

local config = require("xmap.config")
local highlight = require("xmap.highlight")
local lang = require("xmap.lang")
local symbols = require("xmap.symbols")
local treesitter = require("xmap.treesitter")
local navigation = require("xmap.navigation")

local M = {}

-- PURPOSE:
-- - Cap prefix width so relative numbers never widen the minimap layout.
local MAX_RELATIVE_DISTANCE = 999

local function pad_right(text, width)
	text = text or ""
	local len = vim.api.nvim_strwidth(text)
	if len >= width then
		return text
	end
	return text .. string.rep(" ", width - len)
end

local function build_relative_prefix_settings(opts)
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
M.state = {
	bufnr = nil,
	winid = nil,
	main_bufnr = nil,
	main_winid = nil,
	is_open = false,
	last_update = 0,
	update_timer = nil,
	last_relative_update = 0,
	relative_timer = nil,
	line_mapping = {},
	content_by_line = {},
	entry_kinds = {},
	entry_symbols = {},
	structural_nodes = {},
	relative_prefix_settings = nil,
	navigation_anchor_line = nil,
	follow_scheduled = false,
}

local function resolve_main_winid()
	-- PURPOSE:
	-- - Recover the active window that still shows `main_bufnr`.
	if not (M.state.main_bufnr and vim.api.nvim_buf_is_valid(M.state.main_bufnr)) then
		return nil
	end

	local main_winid = M.state.main_winid
	if
		main_winid
		and vim.api.nvim_win_is_valid(main_winid)
		and vim.api.nvim_win_get_buf(main_winid) == M.state.main_bufnr
	then
		return main_winid
	end

	for _, winid in ipairs(vim.api.nvim_list_wins()) do
		if winid ~= M.state.winid and vim.api.nvim_win_get_buf(winid) == M.state.main_bufnr then
			M.state.main_winid = winid
			return winid
		end
	end

	M.state.main_winid = nil
	return nil
end

local function get_relative_base_line(main_winid)
	-- PURPOSE:
	-- - Freeze the relative-number anchor while the minimap is focused.
	local resolved_main_winid = main_winid
	if
		not (
			resolved_main_winid
			and vim.api.nvim_win_is_valid(resolved_main_winid)
			and vim.api.nvim_win_get_buf(resolved_main_winid) == M.state.main_bufnr
		)
	then
		resolved_main_winid = resolve_main_winid()
	end

	local current_line = navigation.get_main_cursor_line(resolved_main_winid)
	if not (M.state.navigation_anchor_line and M.state.winid and vim.api.nvim_win_is_valid(M.state.winid)) then
		return current_line
	end
	if vim.api.nvim_get_current_win() ~= M.state.winid then
		return current_line
	end
	return M.state.navigation_anchor_line
end
M.ns_viewport = highlight.create_namespace("viewport")
M.ns_cursor = highlight.create_namespace("cursor")
M.ns_syntax = highlight.create_namespace("syntax")
M.ns_structure = highlight.create_namespace("structure")
function M.create_buffer()
	local buf_name = "xmap://minimap"
	local existing_buf = vim.fn.bufnr(buf_name)
	if existing_buf ~= -1 and vim.api.nvim_buf_is_valid(existing_buf) then
		pcall(vim.api.nvim_buf_delete, existing_buf, { force = true })
	end

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(buf, "swapfile", false)
	vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(buf, "buflisted", false)
	vim.api.nvim_buf_set_option(buf, "filetype", "xmap")
	vim.api.nvim_buf_set_name(buf, buf_name)
	vim.api.nvim_buf_set_option(buf, "modifiable", true)

	return buf
end
function M.create_window(bufnr)
	local opts = config.get()
	local current_win = vim.api.nvim_get_current_win()
	if opts.side == "left" then
		vim.cmd("topleft vsplit")
	else
		vim.cmd("botright vsplit")
	end

	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, bufnr)
	vim.api.nvim_win_set_width(win, opts.width)
	vim.api.nvim_win_set_option(win, "number", false)
	vim.api.nvim_win_set_option(win, "relativenumber", false)
	vim.api.nvim_win_set_option(win, "cursorline", false)
	vim.api.nvim_win_set_option(win, "wrap", false)
	vim.api.nvim_win_set_option(win, "signcolumn", "no")
	vim.api.nvim_win_set_option(win, "foldcolumn", "0")
	vim.api.nvim_win_set_option(win, "winfixwidth", true)
	vim.api.nvim_win_set_option(win, "fillchars", "eob: ")
	vim.api.nvim_win_set_option(
		win,
		"winhighlight",
		"Normal:XmapBackground,NormalNC:XmapBackground,EndOfBuffer:XmapBackground,SignColumn:XmapBackground,FoldColumn:XmapBackground"
	)
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
function M.render_line(line, line_nr, current_line, all_lines, ctx)
	-- PURPOSE:
	-- - Render one source line into a minimap entry or skip it.
	if not ctx or not ctx.provider then
		return nil
	end

	local trimmed = vim.trim(line)
	local content = nil
	local entry_kind = nil
	local entry_symbol = nil

	if trimmed ~= "" and ctx.provider.is_comment_line and ctx.provider.is_comment_line(trimmed) then
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
		local symbol = ctx.provider.parse_symbol(trimmed, line_nr, all_lines)
		if not symbol then
			return nil
		end
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
function M.render_buffer(main_bufnr, main_winid, current_line_override)
	if not vim.api.nvim_buf_is_valid(main_bufnr) then
		return {}, {}, {}, {}, {}, {}
	end

	local opts = config.get()
	local prefix_settings = build_relative_prefix_settings(opts)
	local current_line = current_line_override or navigation.get_main_cursor_line(main_winid)

	local lines = vim.api.nvim_buf_get_lines(main_bufnr, 0, -1, false)
	local rendered = {}
	local content_by_line = {}
	local entry_kinds = {}
	local entry_symbols = {}
	local line_mapping = {}
	local structural_nodes = {}
	local filetype = vim.api.nvim_buf_get_option(main_bufnr, "filetype")
	local provider = lang.get(filetype)
	if not provider then
		return {}, {}, {}, {}, {}, {}, {}
	end
	if config.is_treesitter_enabled(filetype) then
		structural_nodes = treesitter.get_structural_nodes(main_bufnr, filetype)
	end
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
			table.insert(line_mapping, i)
		end
	end

	return rendered, line_mapping, structural_nodes, prefix_settings, content_by_line, entry_kinds, entry_symbols
end
function M.apply_relative_number_highlighting(minimap_bufnr, main_bufnr, main_winid, current_line_override)
	-- PURPOSE:
	-- - Repaint only prefix/comment/entity highlights on existing rendered lines.
	-- CONSTRAINTS:
	-- - Use cached `content_by_line` instead of reparsing source text.
	if not vim.api.nvim_buf_is_valid(minimap_bufnr) or not vim.api.nvim_buf_is_valid(main_bufnr) then
		return
	end

	local opts = config.get()
	local prefix_settings = M.state.relative_prefix_settings or build_relative_prefix_settings(opts)
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
	highlight.clear(minimap_bufnr, M.ns_syntax)
	local current_line = current_line_override or navigation.get_main_cursor_line(main_winid)
	local minimap_lines = vim.api.nvim_buf_get_lines(minimap_bufnr, 0, -1, false)
	for minimap_line_nr = 1, #minimap_lines do
		local line_text = minimap_lines[minimap_line_nr]
		local source_line_nr = M.state.line_mapping[minimap_line_nr]
		if not source_line_nr then
			goto continue
		end
		local entry_kind = M.state.entry_kinds and M.state.entry_kinds[minimap_line_nr]

		local delta = source_line_nr - current_line
		highlight.apply(minimap_bufnr, M.ns_syntax, "XmapRelativeNumber", minimap_line_nr - 1, 0, number_end)
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
			local _, text_start = line_text:find("^[^%a]*")
			text_start = text_start and text_start + 1

			if text_start and text_start <= #line_text then
				local text_after_numbers = line_text:sub(text_start)

				for _, keyword in ipairs(highlight_keywords) do
					local kw_start, kw_end = text_after_numbers:find("^" .. keyword)
					if kw_start then
						local next_char = text_after_numbers:sub(kw_end + 1, kw_end + 1)
						if next_char ~= "" and next_char:match("[%w_]") then
							goto continue_keyword
						end
						local kw_pos_in_line = text_start - 1 + kw_start - 1
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
						highlight.apply(
							minimap_bufnr,
							M.ns_syntax,
							keyword_hl,
							minimap_line_nr - 1,
							kw_pos_in_line,
							kw_end_pos_in_line
						)
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
function M.apply_syntax_highlighting(minimap_bufnr, main_bufnr, structural_nodes, current_line_override, prefix_settings_override)
	-- PURPOSE:
	-- - Apply structural highlights on top of rendered entries.
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
	highlight.clear(minimap_bufnr, M.ns_structure)
	local line_lookup = {}
	for minimap_line, source_line in ipairs(M.state.line_mapping or {}) do
		line_lookup[source_line] = minimap_line
	end
	local nodes = structural_nodes or treesitter.get_structural_nodes(main_bufnr, filetype)
	for _, node in ipairs(nodes) do
		local hl_group = treesitter.get_highlight_for_type(node.type)
		local source_line = node.start_line + 1
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
	pcall(vim.api.nvim_buf_set_extmark, minimap_bufnr, M.ns_cursor, minimap_line - 1, 0, {
		hl_group = "XmapCursor",
		hl_eol = true,
		hl_mode = "combine",
		priority = 100,
	})
end
function M.update_relative_only()
	-- PURPOSE:
	-- - Refresh prefixes/highlights without reparsing the full buffer.
	if not M.state.is_open or not M.state.bufnr or not M.state.main_bufnr then
		return
	end

	if not vim.api.nvim_buf_is_valid(M.state.bufnr) or not vim.api.nvim_buf_is_valid(M.state.main_bufnr) then
		M.close()
		return
	end

	local main_winid = resolve_main_winid()
	if not main_winid then
		M.follow_current_target()
		return
	end

	local current_line = get_relative_base_line(main_winid)
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
	highlight.clear(M.state.bufnr, M.ns_viewport)
	highlight.clear(M.state.bufnr, M.ns_cursor)
	M.apply_syntax_highlighting(M.state.bufnr, M.state.main_bufnr, M.state.structural_nodes, current_line, prefix_settings)
	M.apply_relative_number_highlighting(M.state.bufnr, M.state.main_bufnr, main_winid, current_line)

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
function M.update()
	if not M.state.is_open or not M.state.bufnr or not M.state.main_bufnr then
		return
	end

	if not vim.api.nvim_buf_is_valid(M.state.bufnr) or not vim.api.nvim_buf_is_valid(M.state.main_bufnr) then
		M.close()
		return
	end

	local main_winid = resolve_main_winid()
	if not main_winid then
		M.follow_current_target()
		return
	end
	local current_line = get_relative_base_line(main_winid)
	local rendered_lines, line_mapping, structural_nodes, prefix_settings, content_by_line, entry_kinds, entry_symbols =
		M.render_buffer(M.state.main_bufnr, main_winid, current_line)
	M.state.line_mapping = line_mapping
	M.state.content_by_line = content_by_line or {}
	M.state.entry_kinds = entry_kinds or {}
	M.state.entry_symbols = entry_symbols or {}
	M.state.structural_nodes = structural_nodes or {}
	if prefix_settings then
		M.state.relative_prefix_settings = prefix_settings
	end
	vim.api.nvim_buf_set_option(M.state.bufnr, "modifiable", true)
	vim.api.nvim_buf_set_lines(M.state.bufnr, 0, -1, false, rendered_lines)
	vim.api.nvim_buf_set_option(M.state.bufnr, "modifiable", false)
	highlight.clear(M.state.bufnr, M.ns_viewport)
	highlight.clear(M.state.bufnr, M.ns_cursor)
	M.apply_syntax_highlighting(M.state.bufnr, M.state.main_bufnr, structural_nodes, current_line, prefix_settings)
	M.apply_relative_number_highlighting(M.state.bufnr, M.state.main_bufnr, main_winid, current_line)
	local main_line = navigation.get_main_cursor_line(main_winid)
	if M.state.winid and vim.api.nvim_win_is_valid(M.state.winid) then
		local is_minimap_focused = vim.api.nvim_get_current_win() == M.state.winid
		if not is_minimap_focused then
			navigation.update_minimap_cursor(M.state.winid, main_line, M.state.line_mapping)
		end
		local minimap_line = vim.api.nvim_win_get_cursor(M.state.winid)[1]
		M.highlight_cursor_line(M.state.bufnr, minimap_line)
	end

	M.state.last_update = vim.loop.now()
end
function M.throttled_update()
	local opts = config.get()
	local now = vim.loop.now()
	if now - M.state.last_update < opts.render.throttle_ms then
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
function M._follow_current_target()
	-- PURPOSE:
	-- - Reattach the minimap to the best supported buffer/window after editor state changes.
	-- ALGORITHM:
	-- - Prefer the current non-minimap window if supported.
	-- - Reuse the existing main buffer when still visible.
	-- - Fall back to any other supported window.
	-- - Close the minimap if no supported target remains.
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
	if M.state.follow_scheduled then
		return
	end
	M.state.follow_scheduled = true
	vim.schedule(function()
		M.state.follow_scheduled = false
		M._follow_current_target()
	end)
end
function M.open()
	if M.state.is_open and M.state.winid and vim.api.nvim_win_is_valid(M.state.winid) then
		return
	end
	local main_bufnr = vim.api.nvim_get_current_buf()
	local main_winid = vim.api.nvim_get_current_win()
	local filetype = vim.api.nvim_buf_get_option(main_bufnr, "filetype")
	if not config.is_filetype_supported(filetype) then
		vim.notify("Minimap not supported for filetype: " .. filetype, vim.log.levels.INFO)
		return
	end
	local bufnr = M.create_buffer()
	local winid = M.create_window(bufnr)
	M.state.bufnr = bufnr
	M.state.winid = winid
	M.state.main_bufnr = main_bufnr
	M.state.main_winid = main_winid
	M.state.is_open = true
	navigation.setup_minimap_keymaps(bufnr, winid, main_bufnr, main_winid)
	M.update()
	M.setup_autocommands()
end
function M.close()
	-- PURPOSE:
	-- - Tear down timers, autocmds, scratch state, and the minimap window.
	if not M.state.is_open then
		return
	end

	local minimap_bufnr = M.state.bufnr
	local minimap_winid = M.state.winid
	if M.state.update_timer then
		M.state.update_timer:stop()
		M.state.update_timer = nil
	end
	if M.state.relative_timer then
		M.state.relative_timer:stop()
		M.state.relative_timer = nil
	end
	pcall(vim.api.nvim_del_augroup_by_name, "XmapUpdate")
	if minimap_winid and vim.api.nvim_win_is_valid(minimap_winid) then
		local tabpage = vim.api.nvim_win_get_tabpage(minimap_winid)
		local wins = vim.api.nvim_tabpage_list_wins(tabpage)

		if #wins > 1 then
			pcall(vim.api.nvim_win_close, minimap_winid, true)
		else
			-- CONSTRAINTS:
			-- - Do not close the last window in the tabpage.
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
	if minimap_bufnr and vim.api.nvim_buf_is_valid(minimap_bufnr) then
		pcall(vim.api.nvim_buf_delete, minimap_bufnr, { force = true })
	end
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
function M.toggle()
	if M.state.is_open then
		M.close()
	else
		M.open()
	end
end
function M.setup_autocommands()
	-- PURPOSE:
	-- - Keep rendering, follow-target, and cursor sync attached to the current main buffer.
	local augroup = vim.api.nvim_create_augroup("XmapUpdate", { clear = true })

	local function sync_main_window_from_event()
		local current_winid = vim.api.nvim_get_current_win()
		if
			current_winid
			and vim.api.nvim_win_is_valid(current_winid)
			and M.state.main_bufnr
			and vim.api.nvim_win_get_buf(current_winid) == M.state.main_bufnr
		then
			M.state.main_winid = current_winid
		end
	end
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = augroup,
		buffer = M.state.main_bufnr,
		callback = function()
			sync_main_window_from_event()
			M.throttled_update()
		end,
	})
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = augroup,
		buffer = M.state.main_bufnr,
		callback = function()
			sync_main_window_from_event()
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
	vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
		group = augroup,
		buffer = M.state.bufnr,
		callback = function()
			if M.state.bufnr and M.state.winid and vim.api.nvim_win_is_valid(M.state.winid) then
				local opts = config.get()
				local main_winid = resolve_main_winid()
				if
					opts.navigation.follow_cursor
					and main_winid
					and vim.api.nvim_win_is_valid(main_winid)
				then
					M.state.navigation_anchor_line = navigation.get_main_cursor_line(main_winid)
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
					local main_winid = resolve_main_winid()
					if M.state.main_bufnr and main_winid then
						navigation.center_main_on_minimap_cursor(
							M.state.winid,
							M.state.main_bufnr,
							main_winid,
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

			local main_winid = resolve_main_winid()
			if not (main_winid and vim.api.nvim_win_is_valid(main_winid)) then
				return
			end

			local main_line = navigation.get_main_cursor_line(main_winid)
			navigation.update_minimap_cursor(M.state.winid, main_line, M.state.line_mapping)
			local minimap_line = vim.api.nvim_win_get_cursor(M.state.winid)[1]
			M.highlight_cursor_line(M.state.bufnr, minimap_line)

			if M.state.main_bufnr and vim.api.nvim_buf_is_valid(M.state.main_bufnr) then
				M.update_relative_only()
			end
		end,
	})
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = augroup,
		buffer = M.state.main_bufnr,
		callback = function()
			sync_main_window_from_event()
			M.update()
		end,
	})
	vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete", "BufUnload" }, {
		group = augroup,
		buffer = M.state.main_bufnr,
		callback = function()
			M.follow_current_target()
		end,
	})
	vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "FileType" }, {
		group = augroup,
		callback = function()
			if not M.state.is_open then
				return
			end

			M.follow_current_target()
		end,
	})
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
function M.is_open()
	return M.state.is_open
end

return M
