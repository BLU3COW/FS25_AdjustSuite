# Contributing to FS25_AdjustSuite

Thanks for helping improve FS25_AdjustSuite.

Danke, dass du FS25_AdjustSuite verbessern moechtest.

## Repository layout

This repository is intentionally structured like the Farming Simulator 25 mod root. Keep the runtime mod files in this layout:

```text
modDesc.xml
lua/
l10n/
dds/
```

GitHub and documentation files live next to that structure:

```text
.github/
README.md
CONTRIBUTING.md
CHANGELOG.md
```

Do not move the mod runtime files into an extra `src/`, `dist/`, or nested `FS25_AdjustSuite/` folder unless the release packaging workflow is changed at the same time.

## What belongs where

- `modDesc.xml`: mod metadata, loaded source files, localization prefix, icon path, multiplayer flag.
- `lua/`: Lua runtime code and module logic.
- `l10n/`: localization XML files.
- `dds/`: mod icon and other DDS assets.
- `.github/`: issue templates, discussion templates, pull request template, and GitHub-only metadata.
- Root documentation: README, contributing guide, changelog, license, and similar project files.

## Before opening a pull request

- Keep changes focused and avoid unrelated cleanup in the same pull request.
- Check that the repository root still represents the mod root.
- Do not commit generated release zip files, local logs, savegames, cache folders, temporary files, or personal test output.
- Update `l10n/` files when changing player-facing text.
- Update `README.md` or `CHANGELOG.md` when behavior, setup, or release-relevant information changes.
- Mention whether the change was tested in Farming Simulator 25.
- Include `log.txt` snippets or screenshots when they help review the change.

## Issues, discussions, and pull requests

- Use Issues for reproducible bugs and concrete implementation tasks.
- Use Discussions for questions, compatibility checks, early ideas, balancing thoughts, and community examples.
- Use Pull Requests for reviewed changes to repository files.

For bugs, please use the issue templates. For support questions or early ideas, please use Discussions first.
