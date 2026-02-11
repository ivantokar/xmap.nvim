.PHONY: test test-swift test-lua test-ts test-tsx test-follow dev clean install-local

# Test with minimal config (default: Swift)
test:
	nvim -u test_config.lua test.swift

# Test with Swift file
test-swift:
	nvim -u test_config.lua test.swift

# Test with Lua file
test-lua:
	nvim -u test_config.lua test.lua

# Test with TypeScript file
test-ts:
	nvim -u test_config.lua test.ts

# Test with TSX file
test-tsx:
	nvim -u test_config.lua test.tsx

# Headless QA regression checks
test-follow:
	nvim --headless -n -i NONE -u test_config.lua -c "lua dofile('scripts/qa_follow_active_buffer.lua')"

# Open for development (uses your actual config)
dev:
	nvim -c "set rtp+=." test.swift

# Clean generated files
clean:
	rm -f profile.log

# Create symlink for local development with lazy.nvim
install-local:
	@echo "Add this to your lazy.nvim config:"
	@echo ""
	@echo "{"
	@echo "  dir = \"$(PWD)\","
	@echo "  dependencies = { \"nvim-treesitter/nvim-treesitter\" },"
	@echo "  config = function()"
	@echo "    require(\"xmap\").setup()"
	@echo "  end,"
	@echo "}"

# Help
help:
	@echo "xmap.nvim development commands:"
	@echo ""
	@echo "  make test        - Test with minimal config (test.swift)"
	@echo "  make test-swift  - Test with Swift file"
	@echo "  make test-lua    - Test with Lua file"
	@echo "  make test-ts     - Test with TypeScript file"
	@echo "  make test-tsx    - Test with TSX file"
	@echo "  make dev         - Open for development with your config"
	@echo "  make clean       - Clean generated files"
	@echo "  make install-local - Show lazy.nvim local config"
	@echo ""
	@echo "Quick reload in Neovim: :luafile reload.lua"
