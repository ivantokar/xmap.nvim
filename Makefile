.PHONY: test test-swift test-lua test-ts test-tsx test-c test-cpp test-follow dev clean install-local

# PURPOSE:
# - Manual smoke and local dev targets.
test:
	nvim -u test_config.lua test.swift

test-swift:
	nvim -u test_config.lua test.swift

test-lua:
	nvim -u test_config.lua test.lua

test-ts:
	nvim -u test_config.lua test.ts

test-tsx:
	nvim -u test_config.lua test.tsx

test-c:
	nvim -u test_config.lua test.c

test-cpp:
	nvim -u test_config.lua test.cpp

test-follow:
	nvim --headless -n -i NONE -u test_config.lua -c "lua dofile('scripts/qa_follow_active_buffer.lua')"

dev:
	nvim -c "set rtp+=." test.swift

clean:
	rm -f profile.log

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

help:
	@echo "xmap.nvim development commands:"
	@echo ""
	@echo "  make test        - Test with minimal config (test.swift)"
	@echo "  make test-swift  - Test with Swift file"
	@echo "  make test-lua    - Test with Lua file"
	@echo "  make test-ts     - Test with TypeScript file"
	@echo "  make test-tsx    - Test with TSX file"
	@echo "  make test-c      - Test with C file"
	@echo "  make test-cpp    - Test with C++ file"
	@echo "  make dev         - Open for development with your config"
	@echo "  make clean       - Clean generated files"
	@echo "  make install-local - Show lazy.nvim local config"
	@echo ""
	@echo "Quick reload in Neovim: :luafile reload.lua"
