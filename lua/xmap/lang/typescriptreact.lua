-- lua/xmap/lang/typescriptreact.lua
-- TypeScript React (TSX) language support for xmap.nvim
--
-- Neovim uses `typescriptreact` as the filetype for `.tsx` files. Most of the parsing
-- rules are shared with TypeScript, but TSX benefits from React-specific heuristics
-- (hook calls + common component wrappers) for a more useful minimap outline.

local ts = require("xmap.lang.typescript")

local M = {}

-- Copy base TypeScript provider surface.
for k, v in pairs(ts) do
  M[k] = v
end

local function append_unique(list, value)
  for _, v in ipairs(list or {}) do
    if v == value then
      return
    end
  end
  table.insert(list, value)
end

M.default_symbol_keywords = vim.deepcopy(ts.default_symbol_keywords or {})
append_unique(M.default_symbol_keywords, "hook")

M.default_highlight_keywords = vim.deepcopy(ts.default_highlight_keywords or ts.default_symbol_keywords or {})
append_unique(M.default_highlight_keywords, "hook")

local function ltrim(text)
  return (text:gsub("^%s+", ""))
end

local function strip_ts_modifiers(text)
  -- Keep consistent with the TypeScript provider: strip leading modifiers for easier matching.
  local out = ltrim(text or "")

  local function strip(pattern)
    local next_out, count = out:gsub(pattern, "", 1)
    if count > 0 then
      out = ltrim(next_out)
      return true
    end
    return false
  end

  while true do
    local changed = false
    changed = strip("^(export)%s+") or changed
    changed = strip("^(default)%s+") or changed
    changed = strip("^(declare)%s+") or changed
    changed = strip("^(abstract)%s+") or changed
    changed = strip("^(public)%s+") or changed
    changed = strip("^(private)%s+") or changed
    changed = strip("^(protected)%s+") or changed
    changed = strip("^(readonly)%s+") or changed
    changed = strip("^(static)%s+") or changed
    changed = strip("^(override)%s+") or changed
    changed = strip("^(async)%s+") or changed

    if not changed then
      break
    end
  end

  return out
end

local function is_pascal_case(name)
  return type(name) == "string" and name:match("^[A-Z]") ~= nil
end

local function parse_hook_call(text)
  local t = ltrim(text or "")

  local hook_name, args

  -- Generic call: useState<T>(...)
  hook_name, _, args = t:match("^React%.(use%u[%w_$]*)%s*(%b<>)%s*%((.*)$")
  if not hook_name then
    hook_name, _, args = t:match("^(use%u[%w_$]*)%s*(%b<>)%s*%((.*)$")
  end

  -- Non-generic call: useEffect(...)
  if not hook_name then
    hook_name, args = t:match("^React%.(use%u[%w_$]*)%s*%((.*)$")
  end
  if not hook_name then
    hook_name, args = t:match("^(use%u[%w_$]*)%s*%((.*)$")
  end

  if not hook_name then
    return nil
  end

  local first_arg = nil
  if type(args) == "string" then
    local arg_trimmed = ltrim(args)
    first_arg = arg_trimmed:match("^([%a_$][%w_$]*)%s*[,)]")
  end

  return hook_name, first_arg
end

local function hook_symbol(hook_name, label)
  local display = "hook " .. hook_name
  if label and label ~= "" then
    display = display .. " " .. label
  end
  return { keyword = "hook", capture_type = "function", display = display }
end

local function function_symbol(name)
  return { keyword = "function", capture_type = "function", display = "function " .. name }
end

local REACT_COMPONENT_WRAPPERS = {
  memo = true,
  forwardRef = true,
  observer = true,
}

local function looks_like_arrow_function(rhs)
  local text = ltrim(rhs or "")
  text = text:gsub("^async%s+", "")

  if text:match("^function") then
    return true
  end

  -- Arrow functions:
  --   (a, b) => ...
  --   a => ...
  --   <T>(a: T) => ...
  if text:match("^%b()%s*=>") then
    return true
  end
  if text:match("^[%w_$]+%s*=>") then
    return true
  end
  if text:match("^<[^>]+>%s*%b()%s*=>") then
    return true
  end
  if text:match("^<[^>]+>%s*[%w_$]+%s*=>") then
    return true
  end

  return false
end

local function is_wrapped_react_component(rhs)
  local t = ltrim(rhs or "")

  local wrapper_name, args

  wrapper_name, _, args = t:match("^React%.([%w_$]+)%s*(%b<>)%s*%((.*)$")
  if not wrapper_name then
    wrapper_name, _, args = t:match("^([%w_$]+)%s*(%b<>)%s*%((.*)$")
  end

  if not wrapper_name then
    wrapper_name, args = t:match("^React%.([%w_$]+)%s*%((.*)$")
  end
  if not wrapper_name then
    wrapper_name, args = t:match("^([%w_$]+)%s*%((.*)$")
  end

  if not wrapper_name or not REACT_COMPONENT_WRAPPERS[wrapper_name] then
    return false
  end

  local first_arg = ltrim(args or "")
  return looks_like_arrow_function(first_arg)
end

local function parse_react_hook_symbol(cleaned)
  -- Direct hook call: `useEffect(...)` / `React.useEffect(...)`
  do
    local hook_name, first_arg = parse_hook_call(cleaned)
    if hook_name then
      return hook_symbol(hook_name, first_arg)
    end
  end

  -- Hook call assigned to a const/let/var:
  --   const value = useMemo(...)
  --   const [value, setValue] = useState(...)
  --   const { value } = useContext(...)
  do
    local kw, lhs, rhs = cleaned:match("^(%a+)%s*(%b[])%s*=%s*(.+)$")
    if (kw == "const" or kw == "let" or kw == "var") and lhs and rhs then
      local hook_name = parse_hook_call(rhs)
      if hook_name then
        local first = lhs:match("([%a_$][%w_$]*)")
        return hook_symbol(hook_name, first)
      end
    end
  end

  do
    local kw, lhs, rhs = cleaned:match("^(%a+)%s*(%b{})%s*=%s*(.+)$")
    if (kw == "const" or kw == "let" or kw == "var") and lhs and rhs then
      local hook_name = parse_hook_call(rhs)
      if hook_name then
        local first = lhs:match("([%a_$][%w_$]*)")
        return hook_symbol(hook_name, first)
      end
    end
  end

  do
    local kw, name, rhs = cleaned:match("^(%a+)%s+([%w_$]+)%s*.-=%s*(.+)$")
    if (kw == "const" or kw == "let" or kw == "var") and name and rhs then
      local hook_name = parse_hook_call(rhs)
      if hook_name then
        return hook_symbol(hook_name, name)
      end
    end
  end

  return nil
end

---Parse TSX/React symbols + hook calls.
---@param line_text string
---@return {keyword:string, capture_type:string, display:string}|nil
function M.parse_symbol(line_text)
  local cleaned = strip_ts_modifiers(line_text or "")
  if cleaned == "" then
    return nil
  end

  -- Ignore decorator lines (Angular/TS ecosystems).
  if cleaned:match("^@") then
    return nil
  end

  -- React hooks: show `hook useX` entries (useful inside components).
  local hook = parse_react_hook_symbol(cleaned)
  if hook then
    return hook
  end

  -- React component wrappers: `const Foo = memo((...) => ...)` should show as a function entry.
  do
    local kw, name, rhs = cleaned:match("^(%a+)%s+([%w_$]+)%s*.-=%s*(.+)$")
    if (kw == "const" or kw == "let" or kw == "var") and name and rhs and is_pascal_case(name) and is_wrapped_react_component(rhs) then
      return function_symbol(name)
    end
  end

  -- Default TypeScript parsing.
  local symbol = ts.parse_symbol(line_text)
  if not symbol then
    return nil
  end

  return symbol
end

-- TSX tends to use const-assigned arrow functions for components. Improve Tree-sitter highlighting
-- by capturing those declarations as @function when possible (fallbacks included).
local QUERY_VARIANTS = {
  [[
    (class_declaration) @class
    (interface_declaration) @class
    (type_alias_declaration) @class
    (enum_declaration) @class

    (function_declaration) @function
    (method_definition) @method

    (lexical_declaration
      (variable_declarator
        name: (identifier) @function
        value: (arrow_function)))
  ]],
}

function M.get_queries()
  local base = {}
  if type(ts.get_queries) == "function" then
    local ok, queries = pcall(ts.get_queries)
    if ok and type(queries) == "table" then
      base = queries
    end
  end

  local out = vim.deepcopy(QUERY_VARIANTS)
  for _, q in ipairs(base) do
    table.insert(out, q)
  end
  return out
end

function M.get_query()
  return M.get_queries()[1]
end

return M
