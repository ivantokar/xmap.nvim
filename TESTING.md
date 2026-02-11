# Testing xmap.nvim Locally

This guide shows you how to test xmap.nvim features locally during development.

## Quick Start

### 1. Test Lua Support (NEW!)

```bash
# Test with the enhanced test.lua file
make test-lua
```

Inside Neovim:
1. Run `:XmapToggle` or press `<leader>mm` to open the minimap
2. Check if these Lua features appear:
   - ✅ Function declarations (global, local, module methods)
   - ✅ Variable declarations (`local var = ...`)
   - ✅ Return statements
   - ✅ Comment markers (TODO, FIXME, NOTE, WARNING, BUG, HACK)
   - ✅ Tree-sitter syntax highlighting

### 2. Test Other Languages

```bash
make test-swift    # Test Swift support
make test-ts       # Test TypeScript support
make test-tsx      # Test TSX/React support
```

### 3. Development Mode

```bash
# Use your actual Neovim config + xmap from current directory
make dev
```

## Available Test Files

The repository includes test files for all supported languages:

- **test.lua** - Lua functions, variables, comments, markers
- **test.swift** - Swift classes, functions, properties, comments
- **test.ts** - TypeScript functions, classes, interfaces, types
- **test.tsx** - TSX/React components, hooks, JSX

## Testing Workflow

### Method 1: Using Makefile (Recommended)

```bash
# 1. Test Lua support
make test-lua

# 2. Inside Neovim:
:XmapToggle              # Open minimap
<leader>mm               # Toggle minimap (alternative)
<leader>mf               # Focus minimap window

# 3. Navigate in minimap:
j/k                      # Move up/down
<CR>                     # Jump to code
q                        # Close minimap

# 4. Hot reload after code changes:
:luafile reload.lua      # Reload xmap without restarting Neovim
```

### Method 2: Manual Testing

```bash
# Start Neovim with test config
nvim -u test_config.lua test.lua

# Or use full path
nvim -u test_config.lua /path/to/your/file.lua
```

### Method 3: Using Your Config

```bash
# Test with your actual Neovim configuration
nvim --cmd "set rtp+=." test.lua
```

## What to Test for Lua Support

### ✅ Function Declarations

The minimap should show:
- `function M.setup` - Module methods
- `function setup_global` - Global functions
- `local function validate_config` - Local functions
- `M.validate = function` - Arrow-style module methods

### ✅ Variable Declarations

The minimap should show:
- `local test_variable = "..."` - Local variables
- `local another_var = 42` - All local declarations

### ✅ Return Statements

The minimap should show:
- `return M` - Module returns
- `return a - b` - Expression returns
- `return nil` - Simple returns

### ✅ Comments and Markers

The minimap should show:
- `TODO: Add error handling` - TODO marker
- `FIXME: Improve performance` - FIXME marker
- `NOTE: This is a test file` - NOTE marker
- `WARNING: Deprecated function` - WARNING marker
- `BUG: This doesn't work` - BUG marker
- `HACK: Quick workaround` - HACK marker
- `--- Documentation comment` - Doc comments

### ✅ Tree-sitter Highlighting

Check that syntax highlighting works:
- Functions should be highlighted with  icon
- Variables should be highlighted with  icon
- Keywords should be highlighted distinctly
- Comments should be visually distinct

## Interactive Testing Commands

Once Neovim is open with xmap loaded:

```vim
" Open/close/toggle minimap
:XmapToggle
:XmapOpen
:XmapClose

" Force refresh
:XmapRefresh

" Focus minimap window
:XmapFocus

" Check if minimap is open (Lua)
:lua print(require("xmap").is_open())

" Get current config (Lua)
:lua vim.print(require("xmap").get_config())

" Update config at runtime (Lua)
:lua require("xmap").update_config({ width = 30 })
```

## Hot Reload During Development

When you make changes to xmap.nvim code:

```vim
" Reload xmap without restarting Neovim
:luafile reload.lua

" Or from command line in another terminal
" Edit code, then in Neovim run the above command
```

The reload script:
1. Closes existing minimap
2. Unloads all xmap modules from memory
3. Reloads xmap with fresh code
4. Prints status messages

## Testing Configuration Changes

Edit `test_config.lua` to test different configurations:

```lua
require("xmap").setup({
  width = 25,          -- Try different widths
  side = "left",       -- Try left side
  auto_open = true,    -- Test auto-open

  filetypes = { "lua", "swift" },  -- Test specific filetypes

  symbols = {
    lua = {
      exclude = { "local" },  -- Test filtering
    },
  },

  treesitter = {
    enable = false,    -- Test without Tree-sitter
  },
})
```

## Debugging Tips

### Check if Lua parser is installed

```vim
:TSInstall lua
:checkhealth nvim-treesitter
```

### Check if filetype is detected

```vim
:set filetype?
" Should show: filetype=lua
```

### Check if xmap recognizes the filetype

```vim
:lua print(require("xmap.config").is_filetype_supported("lua"))
" Should show: true
```

### Check if Lua provider is loaded

```vim
:lua vim.print(require("xmap.lang").supports("lua"))
" Should show: true
```

### Inspect minimap state

```vim
:lua vim.print(require("xmap.minimap").state)
" Shows current minimap state (bufnr, winid, is_open, etc.)
```

### Check Tree-sitter parsing

```vim
" Open in the Lua buffer
:InspectTree

" This shows the Tree-sitter AST
" Verify function/variable nodes are recognized
```

## Performance Testing

Test with large Lua files:

```bash
# Generate a large test file
lua -e 'for i=1,1000 do print("function M.func"..i.."() end") end' > large_test.lua

# Test with it
nvim -u test_config.lua large_test.lua
```

Check that:
- Minimap opens quickly (< 200ms)
- Updates are smooth (no lag when scrolling)
- Memory usage is reasonable

## Troubleshooting

### Minimap doesn't open for .lua files

1. Check filetype is in config:
   ```vim
   :lua vim.print(require("xmap").get_config().filetypes)
   ```

2. Verify Lua provider exists:
   ```bash
   ls -la lua/xmap/lang/lua.lua
   ```

3. Check for errors:
   ```vim
   :messages
   ```

### No syntax highlighting

1. Verify Tree-sitter is enabled:
   ```vim
   :lua print(require("xmap").get_config().treesitter.enable)
   ```

2. Check Lua parser is installed:
   ```vim
   :TSInstall lua
   ```

3. Verify language is in treesitter.languages:
   ```vim
   :lua vim.print(require("xmap").get_config().treesitter.languages)
   ```

### Functions/variables don't appear

Check the Lua provider parse logic:
```vim
:lua local provider = require("xmap.lang.lua")
:lua local result = provider.parse_symbol("function M.test()")
:lua vim.print(result)
" Should show: { keyword = "function", capture_type = "function", display = "..." }
```

## CI/Automated Testing

For headless testing:

```bash
# Run automated tests
make test-follow

# Or manually:
nvim --headless -u test_config.lua -c "lua dofile('scripts/qa_follow_active_buffer.lua')"
```

## Test Checklist

When testing Lua support, verify:

- [ ] Minimap opens for .lua files
- [ ] Global functions appear in minimap
- [ ] Local functions appear in minimap
- [ ] Module methods appear (M.foo = function)
- [ ] Variables appear (local x = ...)
- [ ] Return statements appear
- [ ] TODO/FIXME/NOTE markers appear with warning colors
- [ ] Comments appear (without -- prefix)
- [ ] Tree-sitter syntax highlighting works
- [ ] Icons appear for functions/variables
- [ ] Jumping to code works (`<CR>` in minimap)
- [ ] Minimap updates on text changes
- [ ] Relative distance indicators work
- [ ] Focus/close commands work

## Contributing Tests

When adding features, update:
1. **test.lua** - Add examples of new features
2. **test_config.lua** - Add relevant config options
3. **TESTING.md** - Document how to test the feature
4. **scripts/** - Add automated tests if applicable

---

**Happy Testing! 🧪**
