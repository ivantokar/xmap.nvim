-- lua/xmap/lang/cpp.lua
-- Copyright (c) Ivan Tokar. MIT License.
-- C++ language support for xmap.nvim

local M = {}

-- Keywords recognized by the C++ provider when users do not override lists.
-- These align with major symbol categories surfaced in C++ codebases.
M.default_symbol_keywords = {
	"function",
	"method",
	"class",
	"struct",
	"union",
	"enum",
	"namespace",
	"using",
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
	["new"] = true,
	["delete"] = true,
}

-- Query variants are ordered by preferred richness, then compatibility.
-- The fallback variant keeps extraction working on parser versions with fewer
-- node/capture combinations.
local QUERY_VARIANTS = {
	[[
    (function_definition) @function
    (class_specifier) @class
    (struct_specifier) @class
    (union_specifier) @class
    (enum_specifier) @class
    (namespace_definition) @class
    (declaration) @variable
  ]],
	[[
    (function_definition) @function
    (class_specifier) @class
    (struct_specifier) @class
    (namespace_definition) @class
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

-- Strip common declaration modifiers from the line prefix so downstream symbol
-- pattern matching does not depend on modifier order.
-- Example: `inline constexpr auto foo(...)` -> `auto foo(...)`.
local function strip_modifiers(text)
	local out = ltrim(text)
	local patterns = {
		"^(static)%s+",
		"^(inline)%s+",
		"^(extern)%s+",
		"^(constexpr)%s+",
		"^(consteval)%s+",
		"^(constinit)%s+",
		"^(virtual)%s+",
		"^(explicit)%s+",
		"^(friend)%s+",
		"^(typename)%s+",
	}

	local changed = true
	while changed do
		changed = false
		for _, pattern in ipairs(patterns) do
			local next_out, count = out:gsub(pattern, "", 1)
			if count > 0 then
				out = ltrim(next_out)
				changed = true
			end
		end
	end
	return out
end

function M.parse_symbol(line_text)
	-- Parse symbols from normalized text to support mixed formatting styles.
	local cleaned = strip_modifiers(line_text or "")
	if cleaned == "" then
		return nil
	end

	do
		-- Keep preprocessor macros visible in symbol navigation.
		local macro = cleaned:match("^#%s*define%s+([%w_]+)")
		if macro then
			return { keyword = "define", capture_type = "variable", display = "#define " .. macro }
		end
	end

	if cleaned == "return" or cleaned:match("^return%f[%W]") then
		-- Surface return statements as control-flow anchors similar to other
		-- language providers.
		local rest = vim.trim((cleaned:gsub("^return", "", 1))):gsub(";+$", "")
		local display = "return"
		if rest ~= "" then
			display = display .. " " .. rest
		end
		return { keyword = "return", capture_type = "function", display = display }
	end

	do
		-- Namespace declarations improve orientation in large C++ files.
		local name = cleaned:match("^namespace%s+([%w_]+)")
		if name then
			return { keyword = "namespace", capture_type = "class", display = "namespace " .. name }
		end
	end

	do
		-- Extract named type declarations for class/struct/union/enum blocks.
		local keyword, name = cleaned:match("^(class)%s+([%w_]+)")
			or cleaned:match("^(struct)%s+([%w_]+)")
			or cleaned:match("^(union)%s+([%w_]+)")
			or cleaned:match("^(enum)%s+([%w_]+)")
		if keyword and name then
			return { keyword = keyword, capture_type = "class", display = keyword .. " " .. name }
		end
	end

	do
		-- Modern alias declarations (`using Alias = ...`).
		local alias = cleaned:match("^using%s+([%w_]+)%s*=")
		if alias then
			return { keyword = "using", capture_type = "class", display = "using " .. alias }
		end
	end

	do
		-- Legacy alias declarations (`typedef ... Alias;`).
		local alias = cleaned:match("^typedef%s+.-([%w_]+)%s*;")
		if alias then
			return { keyword = "typedef", capture_type = "class", display = "typedef " .. alias }
		end
	end

	do
		-- Qualified methods (`Type::method(...)`) are labeled as methods to
		-- distinguish them from free functions.
		local scoped = cleaned:match("([%w_~]+::[%w_~]+)%s*%b()%s*[{;]")
		if scoped then
			return { keyword = "method", capture_type = "method", display = "method " .. scoped }
		end
	end

	do
		-- Unqualified function-like signatures.
		local name = cleaned:match("^([%a_~][%w_~]*)%s*%b()%s*[{;]")
		if name and not CONTROL_KEYWORDS[name] then
			return { keyword = "function", capture_type = "function", display = "function " .. name }
		end
	end

	do
		-- Typed function signatures including templates/pointers/references.
		local name = cleaned:match("^[%w_%s%*&:<>,~]+%s+([%a_~][%w_~]*)%s*%b()%s*[{;]")
		if name and not CONTROL_KEYWORDS[name] then
			return { keyword = "function", capture_type = "function", display = "function " .. name }
		end
	end

	return nil
end

function M.is_comment_line(trimmed)
	return trimmed:match("^//")
		or trimmed:match("^/%*")
		or trimmed:match("^%*/")
		or trimmed:match("^%*%s")
		or trimmed == "*"
end

function M.extract_comment(line)
	local trimmed = vim.trim(line)
	-- Normalize line/block comments into plain text for uniform rendering.
	local text = trimmed:gsub("^//+%s*", ""):gsub("^/%*+%s*", ""):gsub("^%*+%s*", ""):gsub("%s*%*/$", "")
	if text == "" then
		return nil, nil, false
	end

	local marker = nil
	-- Marker prefixes receive dedicated styling in minimap output.
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
	-- Truncate for compact minimap rows while retaining original text value.
	if #text > 35 then
		text = text:sub(1, 32) .. "..."
	end

	return text, marker, false, raw_text
end

function M.render_comment(line)
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
