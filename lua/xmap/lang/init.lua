-- PURPOSE:
-- - Lazily load and cache language providers by filetype.
-- CONSTRAINTS:
-- - Cache misses too, so repeated unsupported lookups stay cheap.

local M = {}

local providers = {}

local function load_provider(filetype)
  if type(filetype) ~= "string" or filetype == "" then
    return nil
  end
  local ok, mod = pcall(require, "xmap.lang." .. filetype)
  if not ok or type(mod) ~= "table" then
    return nil
  end

  return mod
end
function M.get(filetype)
  if providers[filetype] ~= nil then
    return providers[filetype] or nil
  end

  local provider = load_provider(filetype)
  providers[filetype] = provider or false
  return provider
end
function M.supports(filetype)
  return M.get(filetype) ~= nil
end

return M
