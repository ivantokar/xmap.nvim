-- AI HINTS: lua/xmap/lang/c.lua
-- AI HINTS: Copyright (c) Ivan Tokar. MIT License.
-- PURPOSE: Provide C-language symbol/comment extraction for xmap minimap.
-- DEPENDENCIES: Neovim Lua API (`vim.*`) and xmap language loader.
-- CONSTRAINTS: Keep provider pure; no buffer/window mutation.
-- STABILITY: Core

local M = {}

-- PURPOSE: Default symbol classes used when user config does not override `symbols.c.keywords`.
-- OUTPUT: Ordered keyword list consumed by symbol filtering/highlighting.
M.default_symbol_keywords = {
	"function",
	"struct",
	"union",
	"enum",
	"typedef",
	"define",
	"return",
}

M.default_highlight_keywords = vim.deepcopy(M.default_symbol_keywords)

local CONTROL_KEYWORDS = {
	["if"] = true,
	["for"] = true,
	["while"] = true,
	["switch"] = true,
	["return"] = true,
	["sizeof"] = true,
}

-- PURPOSE: Query fallbacks ordered from richest -> most compatible.
-- DO: Keep first variant as preferred parse surface.
-- DO NOT: Remove fallback variant without parser-compat evidence.
-- STABILITY: Flexible
local QUERY_VARIANTS = {
	[[
    (function_definition) @function
    (struct_specifier) @class
    (union_specifier) @class
    (enum_specifier) @class
    (type_definition) @class
    (declaration) @variable
  ]],
	[[
    (function_definition) @function
    (struct_specifier) @class
    (enum_specifier) @class
  ]],
}

function M.get_queries()
	return QUERY_VARIANTS
end

function M.get_query()
	return QUERY_VARIANTS[1]
end

local function ltrim(text)
	return (text:gsub("^%s+", ""))
end

-- PURPOSE: Normalize declaration prefixes before pattern-based symbol parsing.
-- INPUT: Raw source line text.
-- OUTPUT: Same line without known leading declaration modifiers.
-- ALGORITHM:
-- AI HINTS: - Trim leading whitespace.
-- AI HINTS: - Iteratively strip known modifiers until no change.
-- CONSTRAINTS: Strip only leading tokens; preserve semantic tail.
local function strip_modifiers(text)
	local out = ltrim(text)
	local changed = true
	while changed do
		changed = false
		local next_out, count = out:gsub("^(static)%s+", "", 1)
		if count > 0 then
			out = ltrim(next_out)
			changed = true
		end
		next_out, count = out:gsub("^(inline)%s+", "", 1)
		if count > 0 then
			out = ltrim(next_out)
			changed = true
		end
		next_out, count = out:gsub("^(extern)%s+", "", 1)
		if count > 0 then
			out = ltrim(next_out)
			changed = true
		end
		next_out, count = out:gsub("^(const)%s+", "", 1)
		if count > 0 then
			out = ltrim(next_out)
			changed = true
		end
	end
	return out
end

function M.parse_symbol(line_text)
	-- PURPOSE: Map one C line to a minimap symbol descriptor or nil.
	-- INPUT: `line_text` (string|nil), may include modifiers/comments/spacing noise.
	-- OUTPUT: Table `{ keyword, capture_type, display }` or nil.
	-- DO:
	-- AI HINTS: - Prefer explicit constructs (`#define`, `return`, type declarations).
	-- AI HINTS: - Avoid control keywords as function names.
	-- CONSTRAINTS: Pattern-only parser; no Tree-sitter dependency here.
	-- AI HINTS: Extend by adding guarded parsing blocks; do not reorder broad regexes before specific cases.
	local cleaned = strip_modifiers(line_text or "")
	if cleaned == "" then
		return nil
	end

	do
		-- PURPOSE: Render preprocessor define as navigable symbol.
		local macro = cleaned:match("^#%s*define%s+([%w_]+)")
		if macro then
			return { keyword = "define", capture_type = "variable", display = "#define " .. macro }
		end
	end

	if cleaned == "return" or cleaned:match("^return%f[%W]") then
		-- PURPOSE: Surface control-flow return markers with optional tail expression.
		local rest = vim.trim((cleaned:gsub("^return", "", 1))):gsub(";+$", "")
		local display = "return"
		if rest ~= "" then
			display = display .. " " .. rest
		end
		return { keyword = "return", capture_type = "function", display = display }
	end

	do
		-- PURPOSE: Detect named type declarations.
		local keyword, name = cleaned:match("^(struct)%s+([%w_]+)")
			or cleaned:match("^(union)%s+([%w_]+)")
			or cleaned:match("^(enum)%s+([%w_]+)")
		if keyword and name then
			return { keyword = keyword, capture_type = "class", display = keyword .. " " .. name }
		end
	end

	do
		-- PURPOSE: Detect typedef aliases as type symbols.
		local alias = cleaned:match("^typedef%s+.-([%w_]+)%s*;")
		if alias then
			return { keyword = "typedef", capture_type = "class", display = "typedef " .. alias }
		end
	end

	do
		-- PURPOSE: Detect untyped/simple function signatures.
		local name = cleaned:match("^([%a_][%w_]*)%s*%b()%s*[{;]")
		if name and not CONTROL_KEYWORDS[name] then
			return { keyword = "function", capture_type = "function", display = "function " .. name }
		end
	end

	do
		-- PURPOSE: Detect typed function signatures (incl. pointer-heavy declarations).
		local name = cleaned:match("^[%w_%s%*]+%s+([%a_][%w_]*)%s*%b()%s*[{;]")
		if name and not CONTROL_KEYWORDS[name] then
			return { keyword = "function", capture_type = "function", display = "function " .. name }
		end
	end

	return nil
end

function M.is_comment_line(trimmed)
	-- PURPOSE: Fast gate for comment-line rendering path.
	-- INPUT: Trimmed line.
	-- OUTPUT: Boolean.
	return trimmed:match("^//")
		or trimmed:match("^/%*")
		or trimmed:match("^%*/")
		or trimmed:match("^%*%s")
		or trimmed == "*"
end

function M.extract_comment(line)
	-- PURPOSE: Normalize comment text and marker metadata for minimap rendering.
	-- INPUT: Raw line.
	-- OUTPUT: `text, marker, false, raw_text` or nil tuple.
	-- CONSTRAINTS: Keep output shape compatible with existing provider interface.
	local trimmed = vim.trim(line)
	local text = trimmed:gsub("^//+%s*", ""):gsub("^/%*+%s*", ""):gsub("^%*+%s*", ""):gsub("%s*%*/$", "")
	if text == "" then
		return nil, nil, false
	end

	local marker = nil
	-- DO: Parse marker prefixes used by current highlight contract.
	if text:match("^TODO:") then
		marker = "TODO"
		text = text:gsub("^TODO:%s*", "")
	elseif text:match("^FIXME:") then
		marker = "FIXME"
		text = text:gsub("^FIXME:%s*", "")
	elseif text:match("^NOTE:") then
		marker = "NOTE"
		text = text:gsub("^NOTE:%s*", "")
	elseif text:match("^WARNING:") then
		marker = "WARNING"
		text = text:gsub("^WARNING:%s*", "")
	elseif text:match("^BUG:") then
		marker = "BUG"
		text = text:gsub("^BUG:%s*", "")
	elseif text:match("^HACK:") then
		marker = "HACK"
		text = text:gsub("^HACK:%s*", "")
	end

	local raw_text = text
	-- CONSTRAINTS: Keep minimap rows compact; preserve non-truncated `raw_text`.
	if #text > 35 then
		text = text:sub(1, 32) .. "..."
	end

	return text, marker, false, raw_text
end

function M.render_comment(line)
	-- PURPOSE: Convert extracted comment tuple into renderer-ready payload.
	-- OUTPUT: `{ kind=\"marker\"|\"comment\", ... }` or nil.
	local text, marker = M.extract_comment(line)
	if marker then
		return { kind = "marker", marker = marker, text = text or "" }
	end
	if text then
		return { kind = "comment", marker = nil, text = text }
	end
	return nil
end

return M
