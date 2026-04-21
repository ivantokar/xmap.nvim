-- lua/xmap/lang/h.lua
-- `.h` defaults to the C provider to keep legacy C headers stable.
-- Projects that use C++ semantics in `.h` can override filetype mapping.
return require("xmap.lang.c")
