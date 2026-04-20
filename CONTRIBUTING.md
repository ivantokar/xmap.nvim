# Contributing to xmap.nvim

Thanks for your interest in contributing! 🎉

## Development setup

1. Fork and clone the repo.
2. Open the plugin root in your terminal.
3. Run tests:

```bash
make test-follow
```

Optional interactive tests:

```bash
make test-lua
make test-swift
make test-ts
make test-tsx
```

See [TESTING.md](TESTING.md) for full details.

## Pull requests

- Keep PRs focused and small when possible.
- Update docs (`README.md`, `TESTING.md`) if behavior changes.
- Add/update tests when you fix bugs or add features.
- Update `CHANGELOG.md` for user-visible changes.

## Commit and release notes

A lightweight conventional style is appreciated:

- `feat:` new features
- `fix:` bug fixes
- `docs:` documentation changes
- `chore:` maintenance

## Reporting issues

Please include:

- Neovim version (`nvim --version`)
- OS + terminal
- minimal config to reproduce
- expected behavior vs actual behavior
