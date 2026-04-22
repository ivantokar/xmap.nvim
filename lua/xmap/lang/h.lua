-- PURPOSE:
-- - Alias `.h` to the C provider by default.
-- CONSTRAINTS:
-- - Preserve legacy C-header behavior unless user config remaps the filetype.
return require("xmap.lang.c")
