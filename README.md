# xmap.nvim (UNDER DEVELOPMENT)

An **Xcode-style minimap** for Neovim with full **keyboard navigation** and **Tree-sitter integration**. Navigate your code with a visual overview that respects your colorscheme.

![xmap.nvim demo](https://via.placeholder.com/800x400?text=Screenshots+Coming+Soon)

## Features

- 📍 **Visual Minimap**: Side-by-side overview of your entire buffer
- ⌨️ **Keyboard-Only Navigation**: No mouse required - navigate with standard Vim motions
- 🎯 **Smart Jump Indicators**: Colored arrows (🟢 up, 🔴 down) with distance and entity names
- 🌳 **Tree-sitter Integration**: Smart structural highlighting with Nerd Font icons for functions, classes, and more
- 🎨 **Colorscheme Aware**: Uses highlight groups - no hard-coded colors
- ⚡ **Performance Optimized**: Throttled updates and efficient rendering
- 🔧 **Fully Configurable**: Customize every aspect to fit your workflow
- 🦾 **Swift-First**: Built with Swift development in mind, works with any language
- 🔍 **Compact Display**: Smaller font with icons for better space utilization

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
  width = 20,              -- Width of minimap window
  side = "right",          -- "right" or "left"
  auto_open = false,       -- Auto-open for supported filetypes

  -- Supported filetypes
  filetypes = {
    "swift", "lua", "typescript", "javascript",
    "python", "rust", "go", "c", "cpp"
  },

  -- Filetypes to exclude
  exclude_filetypes = {
    "help", "terminal", "prompt", "qf",
    "neo-tree", "NvimTree"
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
    languages = {
      "swift", "lua", "typescript", "javascript",
      "python", "rust", "go", "c", "cpp"
    },
  },

  -- Rendering options
  render = {
    mode = "text",          -- "text" or "compact"
    max_line_length = 20,   -- Characters per line in minimap
    show_line_numbers = false,
    viewport_char = "█",    -- Character for viewport indicator
    throttle_ms = 100,      -- Update throttle (milliseconds)
  },

  -- Navigation settings
  navigation = {
    show_relative_line = true,  -- Show jump distance
    indicator_mode = "float",   -- "notify", "float" (recommended), or "virtual"
    auto_center = true,         -- Center view after jump
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
- `<leader>mf` - Focus minimap

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
  treesitter = {
    enable = true,
    highlight_scopes = true,
  },
  render = {
    mode = "text",
    max_line_length = 25,
  },
})
```

### Example: Minimal/Compact Mode

```lua
require("xmap").setup({
  width = 15,
  render = {
    mode = "compact",  -- Use blocks instead of text
  },
  navigation = {
    indicator_mode = "float",  -- Floating window for indicators
  },
})
```

## Tree-sitter Integration

xmap.nvim uses Tree-sitter to provide structural awareness and highlighting. This means:

- **Functions** are highlighted differently from regular code with  icon
- **Classes/Structs/Enums** stand out visually with  icon
- **Variables** are marked with  icon
- **Navigate by structure** - easier to see where functions begin/end
- **Smart indicators** - When navigating, see entity names (e.g., "↑ 15 setupConfig")

### Supported Languages

Out of the box, xmap.nvim includes Tree-sitter queries for:

- Swift (primary focus)
- Lua
- TypeScript/JavaScript
- Python
- Rust
- Go
- C/C++

### Enabling Tree-sitter

Tree-sitter integration is enabled by default. Make sure you have the parsers installed:

```vim
:TSInstall swift lua typescript javascript python rust go c cpp
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
- `XmapKeyword` - Keywords (→ `Keyword`)
- `XmapString` - Strings (→ `String`)
- `XmapNumber` - Numbers (→ `Number`)
- `XmapScope` - Scope indicators (→ `Title`)

### Navigation Indicators

- `XmapRelativeUp` - Jump up indicator (green arrow: `#a6e3a1`)
- `XmapRelativeDown` - Jump down indicator (red arrow: `#f38ba8`)
- `XmapRelativeCurrent` - Current line indicator (→ `DiffText`)
- `XmapRelativeNumber` - Jump distance number (→ `LineNr`, dimmed)
- `XmapRelativeEntity` - Entity name display (→ `Comment`)

### Customizing Highlights

```lua
-- In your init.lua or colorscheme
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
    indicator_mode = "float",  -- Use "float" for colored arrows and entity names
  },
})
```

**Note**: The "notify" mode shows plain text without colors. Use "float" mode for the best visual experience with green/red arrows and entity names.

### Minimap doesn't open for my filetype

Add it to the supported filetypes:

```lua
require("xmap").setup({
  filetypes = { "swift", "lua", "yourfiletype" },
})
```

## Known Limitations

- **1:1 Line Mapping**: Currently, each line in the minimap corresponds to one line in the main buffer. Future versions may support more compact representations.
- **Single Buffer**: One minimap per buffer. Split windows show the same minimap.
- **No Mouse Support**: Designed for keyboard-only navigation (mouse support may be added later).

## Future Ideas

- 🔍 **Search Highlights**: Show search results in minimap
- 📊 **Git Diff Indicators**: Visualize changes in minimap
- 🎯 **Bookmarks/Marks**: Display marks in minimap
- 🔥 **LSP Diagnostics**: Highlight errors/warnings
- 📈 **Code Complexity**: Visual indicators for complex functions
- 🖱️ **Mouse Support**: Click to jump (optional)
- 🔢 **Smart Scaling**: Non-1:1 line mapping for better overview

## Contributing

Contributions are welcome! Feel free to:

- Report bugs
- Suggest features
- Submit pull requests
- Improve documentation
- Add Tree-sitter queries for more languages

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Inspired by Xcode's minimap
- Built on the excellent [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
- Thanks to the Neovim community for their amazing work

---

**Made with ❤️ for Swift developers and Vim enthusiasts**
