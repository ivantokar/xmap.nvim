<p align="center">
<img src="./xmap-logo.png" alt="An Xcode-style minimap for Neovim with full keyboard navigation and Tree-sitter integration. Navigate your code with a visual overview that respects your colorscheme." width="200">
</p>

# xmap.nvim

An **Xcode-style minimap** for Neovim with full **keyboard navigation** and **Tree-sitter integration**. Navigate your code with a visual overview that respects your colorscheme.

## Features

- **Visual Minimap**: Side-by-side overview of your entire buffer
- **Keyboard-Only Navigation**: No mouse required - navigate with standard Vim motions
- **Smart Jump Indicators**: Colored arrows (🟢 up, 🔴 down) with distance and entity names
- **Tree-sitter Integration**: Smart structural highlighting with Nerd Font icons for functions, classes, and more
- **Colorscheme Aware**: Uses highlight groups - no hard-coded colors
- **Performance Optimized**: Throttled updates and efficient rendering
- **Fully Configurable**: Customize every aspect to fit your workflow
- **Swift + TypeScript**: Bundled providers with a pluggable language architecture
- **Compact Display**: Smaller font with icons for better space utilization

## Requirements

- Neovim 0.9.0 or higher
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) (optional, for structural highlighting)

## Installation

### lazy.nvim (recommended)

```lua
{
  "ivantokar/xmap.nvim",
  dependencies = {
    "nvim-treesitter/nvim-treesitter", -- Optional but recommended
  },
  config = function()
    require("xmap").setup({
      -- your configuration here
    })
  end,
}
```

### packer.nvim

```lua
use {
  "ivantokar/xmap.nvim",
  requires = { "nvim-treesitter/nvim-treesitter" }, -- Optional
  config = function()
    require("xmap").setup()
  end
}
```

### vim-plug

```vim
Plug 'nvim-treesitter/nvim-treesitter'  " Optional
Plug 'ivantokar/xmap.nvim'
```

Then in your `init.lua`:

```lua
require("xmap").setup()
```

## Quick Start

After installation, toggle the minimap with `:XmapToggle` or use the default keymap `<leader>mm`.

```lua
-- Minimal configuration
require("xmap").setup()
```

## Configuration

Here's the full default configuration:

```lua
require("xmap").setup({
  -- Window settings
  width = 40,              -- Width of minimap window
  side = "right",          -- "right" or "left" (pinned to tabpage edge)
  auto_open = false,       -- Auto-open for supported filetypes

  -- Supported filetypes
  filetypes = { "swift", "typescript", "typescriptreact" },

  -- Filetypes to exclude
  exclude_filetypes = {
    "help", "terminal", "prompt", "qf",
    "neo-tree", "NvimTree", "lazy"
  },

  -- Keymaps (set to false to disable)
  keymaps = {
    toggle = "<leader>mm",  -- Toggle minimap
    focus = "<leader>mf",   -- Focus minimap window
    jump = "<CR>",          -- Jump to line (inside minimap)
    close = "q",            -- Close minimap (inside minimap)
  },

  -- Tree-sitter integration
  treesitter = {
    enable = true,                    -- Enable Tree-sitter
    highlight_scopes = true,          -- Highlight functions/classes
    languages = { "swift", "typescript", "typescriptreact" },
  },

  -- Symbol filtering per language (keyed by filetype)
  symbols = {
    swift = {
      keywords = {},          -- When empty, uses Swift defaults
      exclude = {},          -- e.g. { "let", "var" }
      highlight_keywords = {}, -- Optional override for keyword highlighting list
    },
    typescript = {
      keywords = {},          -- When empty, uses TypeScript defaults
      exclude = {},
      highlight_keywords = {},
    },
    typescriptreact = {
      keywords = {},          -- When empty, uses TSX defaults (TypeScript + React hooks)
      exclude = {},
      highlight_keywords = {},
    },
  },

  -- Highlight overrides (re-applies on ColorScheme)
  -- highlights = { XmapRelativeNumber = { link = "CursorLineNr", bold = true } }
  highlights = {},

  -- Rendering options
  render = {
    relative_prefix = {
      number_width = 3,
      number_separator = " ",
      separator = " ",
      direction = {
        up = "↑",
        down = "↓",
        current = "·",
      },
    },
    max_line_length = 40,   -- Characters per minimap entry (incl. prefix)
    throttle_ms = 100,      -- Update throttle (milliseconds)
  },

  -- Navigation settings
  navigation = {
    show_relative_line = true,  -- Show jump distance
    auto_center = true,         -- Center view after jump
    follow_cursor = true,       -- Center editor while navigating minimap
  },
})
```

## Usage

### Commands

- `:XmapToggle` - Toggle the minimap on/off
- `:XmapOpen` - Open the minimap
- `:XmapClose` - Close the minimap
- `:XmapRefresh` - Force refresh the minimap
- `:XmapFocus` - Focus the minimap window

### Default Keymaps

**Global** (configurable via `keymaps` option):

- `<leader>mm` - Toggle minimap
- `<leader>mf` - Open/focus minimap

**Inside Minimap** (configurable via `keymaps` option):

- `<CR>` - Jump to line under cursor
- `q` - Close minimap
- `j/k` - Navigate up/down (shows relative jump distance)
- Any Vim motion (`gg`, `G`, `{`, `}`, etc.) - Navigate minimap

### Example: Custom Keymaps

```lua
require("xmap").setup({
  keymaps = {
    toggle = "<leader>mt",
    focus = "<leader>mf",
    jump = "<CR>",
    close = "q",
  },
})
```

### Example: Swift Development Setup

```lua
require("xmap").setup({
  width = 25,
  side = "right",
  auto_open = true,  -- Auto-open for supported files
  filetypes = { "swift" },
  symbols = {
    swift = {
      exclude = { "let", "var" }, -- Hide properties, keep types + functions
      -- Or set an explicit allowlist:
      -- keywords = { "func", "struct", "enum" },
    },
  },
  treesitter = {
    enable = true,
    highlight_scopes = true,
  },
  render = {
    max_line_length = 25,
  },
})
```

## Tree-sitter Integration

xmap.nvim uses Tree-sitter to provide structural awareness and highlighting. This means:

- **Functions** are highlighted differently from regular code with  icon
- **Classes/Structs/Enums** stand out visually with  icon
- **Variables** are marked with  icon
- **Navigate by structure** - easier to see where functions begin/end
- **Smart indicators** - When navigating, see entity names (e.g., "15 ↑ setupConfig")

### Supported Languages

Bundled: **Swift**, **TypeScript**, **TypeScriptReact**.

To add another language later, add a provider module at `lua/xmap/lang/<filetype>.lua` and include the filetype in `filetypes` (and `treesitter.languages` if you want Tree-sitter highlighting).

### Enabling Tree-sitter

Tree-sitter integration is enabled by default. Make sure you have the parsers installed:

```vim
:TSInstall swift typescript tsx
```

To disable Tree-sitter features:

```lua
require("xmap").setup({
  treesitter = {
    enable = false,
  },
})
```

## Highlight Groups

xmap.nvim uses the following highlight groups, all linked to existing groups by default. You can override them in your colorscheme or `init.lua`:

### Main UI

- `XmapBackground` - Minimap window background (→ `Normal`)
- `XmapText` - Normal text in minimap (→ `Comment`)
- `XmapLineNr` - Line numbers if enabled (→ `LineNr`)
- `XmapViewport` - Current viewport region (→ `Visual`)
- `XmapCursor` - Cursor line in minimap (→ `CursorLine`)
- `XmapBorder` - Window border (→ `FloatBorder`)

### Tree-sitter Highlights

- `XmapFunction` - Functions/methods (→ `Function`)
- `XmapClass` - Classes/structs/types (→ `Type`)
- `XmapMethod` - Methods (→ `Function`)
- `XmapVariable` - Variables (→ `Identifier`)
- `XmapComment` - Comments (→ `Comment`)
- `XmapSwiftKeyword` - Keywords (→ `Keyword`)
- `XmapString` - Strings (→ `String`)
- `XmapNumber` - Numbers (→ `Number`)
- `XmapScope` - Scope indicators (→ `Title`)

### Navigation Indicators

- `XmapRelativeUp` - Jump up indicator (→ `DiagnosticOk`)
- `XmapRelativeDown` - Jump down indicator (→ `DiagnosticError`)
- `XmapRelativeCurrent` - Current line indicator (→ `DiagnosticWarn`)
- `XmapRelativeNumber` - Jump distance number (→ `CursorLineNr`, brighter)
- `XmapRelativeKeyword` - Keyword highlight (→ `Keyword`)
- `XmapRelativeEntity` - Entity name display (→ `Identifier`)

### Customizing Highlights

```lua
-- Option A: via config (re-applies on ColorScheme)
require("xmap").setup({
  highlights = {
    XmapRelativeNumber = { link = "CursorLineNr", bold = true },
  },
})

-- Option B: manual (you may need to re-apply after :colorscheme)
vim.api.nvim_set_hl(0, "XmapViewport", { bg = "#3e4451", bold = true })
vim.api.nvim_set_hl(0, "XmapFunction", { fg = "#61afef", italic = true })
vim.api.nvim_set_hl(0, "XmapClass", { fg = "#e5c07b", bold = true })
```

## API

```lua
local xmap = require("xmap")

-- Setup (call once in init.lua)
xmap.setup(opts)

-- Control minimap
xmap.open()      -- Open minimap
xmap.close()     -- Close minimap
xmap.toggle()    -- Toggle minimap
xmap.refresh()   -- Force refresh
xmap.focus()     -- Focus minimap window

-- Query state
xmap.is_open()   -- Returns true if minimap is open

-- Get/update config
local config = xmap.get_config()
xmap.update_config({ width = 30 })
```

## Performance

xmap.nvim is designed to be performant even with large files:

- **Throttled Updates**: Updates are throttled (default: 100ms) to avoid excessive redraws
- **Efficient Rendering**: Only visible portions are processed intensively
- **Smart Highlighting**: Tree-sitter queries are cached and reused
- **Lazy Loading**: Tree-sitter features only activate when available

For very large files (10,000+ lines), consider:

```lua
require("xmap").setup({
  render = {
    throttle_ms = 200,  -- Increase throttle
    mode = "compact",   -- Use compact mode
  },
  treesitter = {
    highlight_scopes = false,  -- Disable structural highlighting
  },
})
```

## Troubleshooting

### Minimap doesn't show Tree-sitter highlights

1. Check if nvim-treesitter is installed: `:checkhealth nvim-treesitter`
2. Ensure parser is installed: `:TSInstall <language>`
3. Check if language is in config: `treesitter.languages`

### Minimap window is too narrow/wide

```lua
require("xmap").setup({
  width = 30,  -- Adjust width
})
```

Or resize at runtime:

```lua
require("xmap").update_config({ width = 30 })
```

### Relative jump indicators don't show or aren't colored

```lua
require("xmap").setup({
  navigation = {
    show_relative_line = true,
  },
})
```

If you still don't see colored arrows/numbers, ensure your colorscheme isn't clearing these highlight groups: `XmapRelativeUp`, `XmapRelativeDown`, `XmapRelativeCurrent`, `XmapRelativeNumber`.

### Minimap doesn't open for my filetype

Bundled language support is provided via provider modules (e.g. `lua/xmap/lang/swift.lua`). To add a new filetype, create a provider module and include the filetype:

```lua
require("xmap").setup({
  filetypes = { "swift", "yourfiletype" },
})
```

## Known Limitations

- **Outline-Only View**: The minimap currently renders a curated list of entries (symbols + comments/markers), not every source line.
- **Single Minimap**: One minimap window that follows the active buffer (supported filetypes).
- **No Mouse Support**: Designed for keyboard-only navigation (mouse support may be added later).

## Future Ideas

- 🔍 **Search Highlights**: Show search results in minimap
- 📊 **Git Diff Indicators**: Visualize changes in minimap
- 🎯 **Bookmarks/Marks**: Display marks in minimap
- 🔥 **LSP Diagnostics**: Highlight errors/warnings
- 📈 **Code Complexity**: Visual indicators for complex functions
- 🖱️ **Mouse Support**: Click to jump (optional)
- 🔢 **Smart Scaling**: Adaptive density for large files (more/less detail)

## Contributing

Contributions are welcome! Feel free to:

- Report bugs
- Suggest features
- Submit pull requests
- Improve documentation
- Add language providers for more languages

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Inspired by Xcode's minimap
- Built on the excellent [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
- Thanks to the Neovim community for their amazing work

---

**Made with ❤️ for Swift/TypeScript developers and Vim enthusiasts**
