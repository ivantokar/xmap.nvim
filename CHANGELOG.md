# Changelog

All notable changes to xmap.nvim will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-12-11

### Added
- **Swift MARK Comment Support**: Automatically detects and displays Swift MARK comments as section headers
  - Supports `// MARK:`, `// MARK: -`, and other variants
  - MARKs shown with `━` prefix for visual distinction
  - Configurable via `swift.show_marks` and `swift.mark_patterns` options

- **Structural Navigation**: Display function/class/struct names with Tree-sitter
  - Extract actual symbol names (not just types)
  - Hierarchical indentation up to 4 levels
  - Smart nesting detection

- **Dynamic Relative Indicators**: Real-time distance indicators next to each item
  - `[↓ N]` for items below cursor
  - `[↑ N]` for items above cursor
  - `[•]` for current position
  - Updates automatically as cursor moves (50ms throttle)

- **Editor-Matching Syntax Highlighting**: Uses Treesitter highlight groups
  - `@function`, `@type`, `@property`, `@constructor`, etc.
  - Matches your editor's colorscheme automatically
  - Separate highlights for Swift types: class, struct, enum, protocol, extension

- **Swift-Only Focus**: Optimized exclusively for Swift development
  - Enhanced Tree-sitter queries for Swift
  - Support for Swift-specific constructs (init, deinit, subscript, extension)
  - Removed other language support for simplicity

### Changed
- **Block-Based Rendering**: Minimap now shows structural overview instead of 1:1 line mapping
  - Scales content to fit window height
  - Each minimap entry represents a code structure
  - More compact and useful overview

- **Configuration Defaults**:
  - `filetypes`: Now `{ "swift" }` only
  - `treesitter.languages`: Now `{ "swift" }` only
  - `render.throttle_ms`: Reduced to 50ms for responsive indicators
  - `navigation.show_relative_line`: Disabled by default (indicators always visible)

### Fixed
- **Notification Spam**: Removed CursorMoved autocmd that triggered notifications on every cursor move
- **Line Mapping**: Proper translation between minimap entries and source lines
- **Highlight Performance**: Optimized syntax highlighting with per-node type storage

### Technical Details
- Version: 1.0.0
- Requires: Neovim 0.9+
- Dependencies: nvim-treesitter (optional but recommended)
- Lines of Code: ~1,700 lines of Lua

## [0.1.0] - 2025-12-11 (Initial Development)

### Added
- Initial plugin structure
- Basic minimap functionality
- Tree-sitter integration foundation
- Configuration system
- User commands (`:XmapToggle`, `:XmapOpen`, `:XmapClose`)

[1.0.0]: https://github.com/ivantokar/xmap.nvim/releases/tag/v1.0.0
[0.1.0]: https://github.com/ivantokar/xmap.nvim/commits/initial
