-- lua/xmap/lang/h.lua
-- PURPOSE: Alias `h` headers to C provider by default.
-- DO: Preserve legacy C-header behavior as default mapping.
-- AI HINTS: If project expects C++ semantics for `.h`, override filetype mapping in user config.
-- STABILITY: Flexible
return require("xmap.lang.c")
