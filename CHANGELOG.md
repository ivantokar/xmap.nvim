# Changelog

## 0.8.0 - 2026-04-21

- Add bundled C and C++ providers (`c`, `cpp`) with symbol extraction for functions, types (`struct`/`class`/`enum`/`union`), aliases (`typedef`/`using`), macros (`#define`), and return statements.
- Add C/C++ comment support for single-line and block comment entries, including marker rendering for `TODO`, `FIXME`, `NOTE`, `WARNING`, `BUG`, and `HACK`.
- Add header aliases with default provider mapping: `h` -> C provider, `hpp` -> C++ provider (plus C++ aliases `cc` and `cxx`).
- Extend default config and docs to include C-family filetypes in `filetypes`, `treesitter.languages`, and language symbol configuration.

### Utility updates

- Add language smoke coverage for `c`, `cpp`, `h`, and `hpp` in `scripts/qa_smoke_languages.lua`.
- Add manual test targets `make test-c` and `make test-cpp`.
- Add C/C++ fixture files (`test.c`, `test.cpp`) and update testing/docs guidance for local validation.
- Add detailed in-file maintenance comments to the new C/C++ providers to document query fallbacks, parsing heuristics, and alias behavior.

## 0.7.0 - 2026-02-11

- Add bundled Lua provider (`lua`) with minimap entries for function declarations (global, local, module methods), variable declarations, and return statements.
- Support Lua comment detection and rendering (including TODO/FIXME/NOTE/WARNING/BUG/HACK markers).

## 0.6.0 - 2026-01-27

- Add bundled Markdown provider (`markdown`) with minimap entries for headings (ATX + Setext), fenced code blocks, images, links, and HTML tags.
- Add Markdown heading highlight groups (`XmapMarkdownH1`-`XmapMarkdownH6`, `XmapMarkdownHeadingText`) and apply heading highlighting in the minimap.
- Extend language providers: `parse_symbol(line_text, line_nr?, all_lines?)` and optional `icon` on returned symbol entries.

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
- Per-language keyword filtering for the minimap list (`symbols.<filetype>.*keywords*`, `exclude`, `highlight_keywords`).
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
