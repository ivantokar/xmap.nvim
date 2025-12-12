# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

xmap.nvim is a Neovim plugin that provides an Xcode-style minimap with Tree-sitter integration. It's written in Lua and designed for Neovim 0.9.0+. The plugin displays a side-by-side code overview with keyboard-only navigation and structural syntax highlighting.

## Development Commands

### Testing the Plugin

```bash
# Open Neovim with the plugin loaded from local directory
nvim --cmd "set rtp+=." test.lua

# Test plugin commands interactively
:XmapToggle    # Toggle minimap
:XmapOpen      # Open minimap
:XmapClose     # Close minimap
:XmapRefresh   # Force refresh
:XmapFocus     # Focus minimap window
```

### Testing with Different Filetypes

```lua
-- In Neovim, create test files for different languages
:e test.swift
:e test.lua
:e test.ts

-- Each should trigger appropriate Tree-sitter highlighting
```

## Architecture

### Module Structure

The plugin follows a modular architecture with clear separation of concerns:

**Core Modules (lua/xmap/):**
- `init.lua` - Main API and entry point. Exposes public functions (`setup()`, `open()`, `close()`, `toggle()`, etc.) and initializes all submodules
- `config.lua` - Configuration management with defaults. Handles user config merging and filetype validation
- `minimap.lua` - Minimap window and buffer management. Core rendering logic with 1:1 line mapping between minimap and main buffer
- `navigation.lua` - Cursor navigation and jumping between minimap and main buffer. Handles relative position indicators
- `treesitter.lua` - Tree-sitter integration for structural syntax highlighting. Contains language-specific queries
- `highlight.lua` - Highlight group definitions and application. All groups link to standard Neovim highlights by default

**Plugin Loader:**
- `plugin/xmap.lua` - Defines Vim commands (`:XmapToggle`, etc.) and prevents double-loading

### Key Design Patterns

**State Management:**
- `minimap.lua` maintains plugin state in `M.state` table (bufnr, winid, main_bufnr, main_winid, is_open)
- State is reset on close and validated on each update
- Uses namespaces for different highlight types (viewport, cursor, syntax)

**Update Throttling:**
- `minimap.throttled_update()` prevents excessive redraws using `throttle_ms` config (default 100ms)
- Timer-based deferral when updates come too quickly
- Immediate updates on buffer write

**Window Management:**
- Minimap uses vertical split (not floating window) for better integration
- Window width is fixed (`winfixwidth = true`)
- Always returns focus to main window after operations

**Tree-sitter Integration:**
- Language-specific queries defined as strings in `treesitter.queries` table
- Graceful degradation when nvim-treesitter not installed
- Query captures map to highlight groups via `get_highlight_for_type()`

### Data Flow

1. **User Action** → User calls `:XmapToggle` or `<leader>mm`
2. **API Call** → `init.lua` routes to `minimap.toggle()`
3. **Window Creation** → `minimap.open()` creates buffer and split window
4. **Rendering** → `minimap.render_buffer()` processes all lines from main buffer
5. **Highlighting** → `minimap.apply_syntax_highlighting()` uses Tree-sitter to identify structural nodes
6. **Update Loop** → Autocommands trigger `minimap.throttled_update()` on text/cursor changes
7. **Navigation** → User presses `<CR>` in minimap → `navigation.jump_to_line()` moves cursor in main buffer

### Line Rendering Logic

Two rendering modes (`config.render.mode`):
- **"text"** (default): Truncates and trims actual text to `max_line_length` characters with Nerd Font icons for structural elements
- **"compact"**: Uses block characters (█, ▓, ░, ·) based on code density calculation

**Icon Integration**: The `get_line_icon()` function checks if a line is the start of a structural element (function, class, variable) and prepends the appropriate Nerd Font icon. Icons are retrieved via `treesitter.get_icon_for_type()`.

1:1 line mapping means minimap line N always corresponds to main buffer line N.

### Tree-sitter Query System

Each language has a query string that identifies structural elements:
- `@class` captures: classes, structs, protocols, enums, interfaces
- `@function` captures: functions, methods, init/deinit, arrow functions
- `@variable` captures: variable declarations, properties

Queries are parsed on-demand and cached by Tree-sitter. Results are sorted by start line and highlighted with corresponding `Xmap*` highlight groups.

## Important Implementation Details

### Highlight Namespace Isolation

Three separate namespaces prevent highlight conflicts:
- `ns_viewport`: Highlights visible region in main buffer (uses `XmapViewport`)
- `ns_cursor`: Highlights current cursor line (uses `XmapCursor`)
- `ns_syntax`: Tree-sitter structural highlights (uses `XmapFunction`, `XmapClass`, etc.)

Namespaces are cleared before each re-application to prevent stale highlights.

### Filetype Support Validation

Two-step validation in `config.is_filetype_supported()`:
1. Check if filetype is in `exclude_filetypes` (early return false)
2. Check if filetype is in `filetypes` (return true)

This allows users to explicitly exclude filetypes that would otherwise be supported.

### Relative Jump Indicators

When navigating in minimap with `j`/`k`, `navigation.show_relative_indicator()` displays distance to target with improved formatting:
- Format: `arrow > number > entity` (e.g., "↑ 15 setupConfig")
- Arrow colors: Green (↑) for up, Red (↓) for down
- Number is dimmed (uses `XmapRelativeNumber` highlight group)
- Entity name extracted via `get_entity_at_line()` using pattern matching on Tree-sitter structural nodes
- Three display modes: `notify` (plain text), `float` (colored floating window with syntax highlighting - recommended), `virtual` (not yet implemented)

The indicator:
1. Compares main buffer cursor line with minimap cursor line to calculate relative distance
2. Extracts entity name (function/class name) at target line using Tree-sitter nodes
3. Formats message with colored arrow, dimmed number, and entity name
4. In "float" mode, applies individual highlight groups to each component

### Autocommand Cleanup and Buffer Close Handling

All minimap-specific autocommands are created in `XmapUpdate` augroup. The minimap automatically closes when:
1. Main buffer is wiped out (`BufWipeout`)
2. Main buffer is deleted (`BufDelete`)
3. Main buffer is unloaded (`BufUnload`)
4. Buffer becomes invalid (checked on `BufEnter`/`WinEnter`)

When minimap closes via `M.close()`:
1. Update timers are stopped and cleared
2. Autocommand group `XmapUpdate` is deleted using `nvim_del_augroup_by_name`
3. Minimap window is closed
4. Minimap buffer is deleted
5. State is reset to default values

This ensures proper cleanup and prevents orphaned minimaps when buffers are closed.

## Icon System

The plugin uses Nerd Font icons to visually distinguish code structures in the minimap:

**Icon Mapping** (in `treesitter.lua`):
- Functions/Methods:  (`nf-cod-symbol_method`)
- Classes/Structs:  (`nf-cod-symbol_class`)
- Variables:  (`nf-cod-symbol_variable`)
- Comments:  (`nf-cod-comment`)

**How It Works**:
1. `minimap.get_line_icon(bufnr, line_nr)` checks if a line is the start of a structural element
2. Queries Tree-sitter structural nodes for the buffer
3. If line matches a node's `start_line`, retrieves icon via `treesitter.get_icon_for_type(node.type)`
4. Icon is prepended to the rendered line text with a space separator
5. Max line length is adjusted to account for icon width (2 characters)

To add more icons, update the `get_icon_for_type()` function in `treesitter.lua` with new mappings.

## Adding Language Support

To add a new language:

1. **Add to default filetypes** in `config.lua`:
```lua
filetypes = { "swift", "lua", "typescript", "javascript", "python", "rust", "go", "c", "cpp", "ruby" }
```

2. **Add Tree-sitter query** in `treesitter.lua`:
```lua
ruby = [[
  (class) @class
  (module) @class
  (method) @function
  (singleton_method) @function
  (assignment) @variable
]],
```

3. **Ensure parser is installed**:
```vim
:TSInstall ruby
```

Query syntax follows Tree-sitter query language. Use `:InspectTree` in Neovim to explore node types for your target language.

## Extending Functionality

### Adding New Highlight Groups

1. Define in `highlight.lua`:
```lua
M.groups = {
  XmapNewGroup = { link = "SomeExistingGroup" },
}
```

2. Use in rendering or highlighting code:
```lua
highlight.apply(bufnr, namespace, "XmapNewGroup", line, col_start, col_end)
```

### Adding Configuration Options

1. Add default in `config.lua`:
```lua
M.defaults = {
  new_option = {
    enabled = true,
    value = 42,
  },
}
```

2. Access in code:
```lua
local opts = config.get()
if opts.new_option.enabled then
  -- use opts.new_option.value
end
```

3. Document in README.md configuration section

## Testing Considerations

- Test with and without nvim-treesitter installed (graceful degradation)
- Test with excluded filetypes (should not open minimap)
- Test window resize behavior (`VimResized` autocommand)
- Test with very large files (10,000+ lines) to validate throttling
- Test rapid text changes to ensure throttle timer works correctly
- Verify highlight groups work with different colorschemes
