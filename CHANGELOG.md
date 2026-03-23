# Changelog

## Unreleased

### New Features

- feat: add multiple window decoration styles for code blocks (`macos`, `windows`, `default`).
- feat: add Typst code-annotations hot-fix with annotation markers, circled numbers, and bidirectional linking.
- feat: add `hotfix.quarto-version` threshold to auto-disable temporary hot-fixes when Quarto reaches a specified version.

### Bug Fixes

- fix: HTML-escape auto-generated filename in code block headers to prevent XSS.
- fix: skylighting hot-fix now respects custom `wrapper` name instead of hardcoding `code-window-circled-number`.

### Style

- style: adjust padding and height for title bar in code window.

### Refactoring

- refactor: consolidate `skylighting-fix` option into nested `hotfix` configuration key with `code-annotations` and `skylighting` toggles.
- refactor: introduce `main.lua` entry point for filter assembly and dependency wiring.
- refactor: move hotfix modules (`code-annotations.lua`, `skylighting-typst-fix.lua`) into `_modules/hotfix/`.
- refactor: split Typst function definitions so annotation helpers are only injected when at least one hot-fix is active.
- refactor: update Typst processing to return block sandwich.
- refactor: use utility functions for code-window extension.

## 0.1.1 (2026-03-01)

### Style

- style: tweak traffic lights size.

## 0.1.0 (2026-02-27)

### New Features

- feat: Initial release.
