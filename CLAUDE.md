# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

xmap.nvim is a Neovim plugin that provides an Xcode-style minimap with Tree-sitter integration. It's written in Lua and designed for Neovim 0.9.0+. The plugin displays a side-by-side code overview with keyboard-only navigation and structural syntax highlighting.

## Development Commands

### Testing the Plugin

```bash
# Open Neovim with the plugin loaded from local directory
nvim --cmd "set rtp+=." test.swift

# Test plugin commands interactively
:XmapToggle    # Toggle minimap
:XmapOpen      # Open minimap
:XmapClose     # Close minimap
:XmapRefresh   # Force refresh
:XmapFocus     # Focus minimap window
```

### Testing

```lua
:e test.swift
```

## Architecture

### Module Structure

The plugin follows a modular architecture with clear separation of concerns:

**Core Modules (lua/xmap/):**
- `init.lua` - Main API and entry point. Exposes public functions (`setup()`, `open()`, `close()`, `toggle()`, etc.) and initializes all submodules
- `config.lua` - Configuration management with defaults. Handles user config merging and filetype validation
- `minimap.lua` - Minimap window/buffer management and rendering pipeline. Builds a source-line mapping for rendered entries.
- `navigation.lua` - Jumping/centering between minimap and main buffer. Resolves minimap-line → source-line via `minimap.state.line_mapping`.
- `treesitter.lua` - Tree-sitter integration for structural syntax highlighting (language queries come from providers)
- `highlight.lua` - Highlight group definitions and application. All groups link to standard Neovim highlights by default
- `lang/` - Language providers (`lang/swift.lua`, etc.)

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
- Language queries provided by `lua/xmap/lang/<filetype>.lua`
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

The minimap renders a curated list of entries (not every source line):
- **Symbols**: language provider parses declaration lines (e.g. `func`, `struct`, `enum`)
- **Comments/markers**: provider can render comment lines and MARK/TODO/FIXME-style markers

**Icon Integration**: Rendering uses Nerd Font icons per symbol type via `treesitter.get_icon_for_type()`.

Because the minimap is a filtered list, navigation relies on:
- `minimap.state.line_mapping`: minimap-line (1-indexed) → source-line (1-indexed)
- `navigation.jump_to_line()` resolves through that mapping when present

### Tree-sitter Query System

Each language has a query string that identifies structural elements:
- `@class` captures: classes, structs, protocols, enums, interfaces
- `@function` captures: functions, methods, init/deinit
- `@variable` captures: variable declarations, properties

Queries are parsed on-demand and cached by Tree-sitter. Results are sorted by start line and highlighted with corresponding `Xmap*` highlight groups.

## Important Implementation Details

### Highlight Namespace Isolation

Four separate namespaces prevent highlight conflicts:
- `ns_viewport`: Highlights visible region in main buffer (uses `XmapViewport`)
- `ns_cursor`: Highlights current cursor line (uses `XmapCursor`)
- `ns_syntax`: Relative prefix + comment/keyword highlights (uses `XmapRelative*`, `XmapComment*`, etc.)
- `ns_structure`: Tree-sitter structural highlights (uses `XmapFunction`, `XmapClass`, etc.)

Namespaces are cleared before each re-application to prevent stale highlights.

### Filetype Support Validation

Two-step validation in `config.is_filetype_supported()`:
1. Check if filetype is in `exclude_filetypes` (early return false)
2. Check if filetype is in `filetypes` and a language provider exists (e.g. `xmap.lang.swift`)

This allows users to explicitly exclude filetypes that would otherwise be supported.

### Relative Prefix (Distance + Direction)

Each rendered minimap entry is prefixed with the distance/direction relative to a base line:
- Format is configurable via `render.relative_prefix` (number width, separators, direction symbols/letters)
- Highlighted via `XmapRelativeNumber` and `XmapRelativeUp/Down/Current`
- The base line is typically the main cursor line, but can be “anchored” while the minimap is focused for a more stable navigation experience

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
1. The language provider (`xmap.lang.<filetype>`) parses a source line into a symbol item (keyword + kind)
2. Rendering maps the symbol kind to an icon via `treesitter.get_icon_for_type()`
3. Icon is prepended to the rendered line text with a space separator
4. Text is truncated to `render.max_line_length`

To add more icons, update the `get_icon_for_type()` function in `treesitter.lua` with new mappings.

## Adding Language Support

To add a new language:

1. **Create a provider module** at `lua/xmap/lang/<filetype>.lua` that implements:
   - `get_query()` (Tree-sitter query, optional)
   - `parse_symbol(line)` (extract keyword/type/name for rendering)
   - `render_comment(line, line_nr, all_lines)` (optional)

2. **Enable the filetype** in your config:
```lua
require("xmap").setup({ filetypes = { "swift", "ruby" } })
```

3. **Ensure parser is installed (optional)**:
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
