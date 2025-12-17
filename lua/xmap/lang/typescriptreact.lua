-- lua/xmap/lang/typescriptreact.lua
-- TypeScript React (TSX) language support for xmap.nvim
--
-- Neovim uses `typescriptreact` as the filetype for `.tsx` files. Most of the parsing
-- rules are shared with TypeScript, so we reuse the same provider.

return require("xmap.lang.typescript")

