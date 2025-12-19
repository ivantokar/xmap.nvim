# Changelog

## 0.5.1 - 2025-12-19

- Hide variable/property keywords from default symbol lists (unless they are functions).
- Render commented-out declarations as symbol entries (comment icon + symbol icon).
- Use warning highlights for MARK/TODO/FIXME/NOTE/WARNING/BUG marker lines.

## 0.5.0 - 2025-12-18

- Add TSX (typescriptreact) React hook entries (`hook useX`) to the minimap (incl. destructuring/assignments).
- Improve TSX Tree-sitter structural highlighting (captures const arrow-function declarations).
- Pin minimap split to the tabpage edge for `side="left"` / `side="right"`.
- Make focus keymap (`<leader>mf`) open the minimap if needed.
- Add `return` entries for Swift/TypeScript/TSX.
- Fix `reload.lua` to not override supported `filetypes` during hot-reload.

## 0.4.0 - 2025-12-17

- Add bundled TypeScript (`typescript`) and TSX (`typescriptreact`) language providers.
- Detect JSX comment lines in TSX (`{/* ... */}`) for minimap comment entries.
- Collapse multi-line `/* ... */` comments to a single minimap entry (first meaningful line only).
- Resolve Tree-sitter language names for filetypes like `typescriptreact` (→ `tsx`) to improve query parsing.

## 0.3.0 - 2025-12-16

- Swift-only bundled support with provider-based language architecture (easy to add new languages via `lua/xmap/lang/<filetype>.lua`).
- Per-language keyword filtering for the minimap list (`symbols.<filetype>.keywords`, `exclude`, `highlight_keywords`).
- Relative prefix improvements: number-first format, configurable direction indicators, configurable spacing (`number_separator`, `separator`).
- Comment entries now render without `//` / `///` prefixes (shows only the comment text).
- Brighter relative distance numbers by default (`XmapRelativeNumber` → `CursorLineNr`) and configurable highlight overrides that persist across `:colorscheme`.
- More robust Tree-sitter query handling with Swift fallbacks and query caching to reduce first-run warnings.
- Fix prefix padding for multi-byte direction icons (removes extra space for the current-line dot).

## 0.2.1 - 2025-12-15

- Fix minimap following active buffer when switching windows/buffers.
- Close minimap when the last supported buffer is closed.
- Make minimap jump action follow the current target buffer.

## 0.2.0 - 2025-12-13

- Fix minimap cursorline rendering and theme compatibility.
- Add comment and marker entries to the minimap list.
- Improve structural icons and keyword highlighting.
- Add `navigation.follow_cursor` to center the main editor while navigating the minimap.
- Remove virtual-text indicators and reduce background artifacts.
