# OSS & Publishing Checklist

This repository now includes baseline OSS hygiene:

- ✅ `LICENSE` (MIT)
- ✅ `CODE_OF_CONDUCT.md`
- ✅ `CONTRIBUTING.md`
- ✅ `SECURITY.md`
- ✅ `CODEOWNERS`
- ✅ Issue + PR templates
- ✅ Dependabot for GitHub Actions
- ✅ CI (Neovim smoke) and release workflows

## Branch protection for `main`

Protection config is stored at:

- `.github/branch-protection/main.json`

Apply it with:

```bash
.github/scripts/configure-branch-protection.sh
```

This enforces common OSS defaults:

- required checks (`ci / smoke-tests (pull_request)`)
- up-to-date branch before merge
- 1 approving review
- code owner review
- stale review dismissal
- conversation resolution
- no force-push / no delete
- linear history
- apply to admins too

## Release process

- Update `CHANGELOG.md` with `## X.Y.Z - YYYY-MM-DD`
- Tag and push:

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

- `release.yml` creates a GitHub release automatically on `vX.Y.Z` tags.
- Optional: trigger release manually (`workflow_dispatch`) and pass a pushed tag.

## Neovim plugin listing / discovery (common practice)

To maximize discoverability:

1. Keep README clear (install + config + screenshots/gif).
2. Use semantic tags (`vX.Y.Z`) and changelog entries.
3. Add repository topics on GitHub:
   - `neovim`
   - `neovim-plugin`
   - `lua`
   - `treesitter`
   - `minimap`
4. Submit to plugin lists:
   - `rockerBOO/awesome-neovim` (PR)
   - Optional curated lists/blog posts/newsletters
5. Keep `LICENSE` and maintenance signals visible (CI badge, recent releases).

> Note: aggregators like NeovimCraft generally ingest GitHub metadata automatically once the repo is public and tagged.
