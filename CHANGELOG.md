# Changelog

## Unreleased

### Bug Fixes

- fix: preserve code-annotation structure for HTML/Reveal.js auto-filename blocks.

## 1.0.1 (2026-04-10)

### Bug Fixes

- fix: reduce Reveal.js code-window title bar height by 35% so it is proportional to slide content.

## 1.0.0 (2026-03-29)

### New Features

- feat: derive Typst window chrome colours from page background for dark theme support.

## 0.4.0 (2026-03-29)

### Bug Fixes

- fix: unwrap Quarto's `DecoratedCodeBlock` Div to prevent double filename wrapping in Typst output.
- fix: evaluate theorem/example title strings as Typst markup so inline code renders correctly instead of being stringified.
- fix: normalise code blocks with no or unknown language class to `default` for consistent styling across all formats.
- fix: default to `#` comment symbol for unknown code block languages (`default`, `txt`, etc.) in annotation detection.
- fix: support code annotations with `syntax-highlighting: idiomatic` (native Typst highlighting) via a `show raw.line` rule.

### New Features

- feat: replace global `hotfix.quarto-version` with per-hotfix thresholds for independent auto-disable.

### Refactoring

- refactor: extract language normalisation into dedicated `_modules/language.lua` module.

## 0.3.0 (2026-03-23)

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
- refactor: Replace monolithic `utils.lua` with focused modules (`string.lua`, `logging.lua`, `metadata.lua`, `pandoc-helpers.lua`, `html.lua`, `paths.lua`, `colour.lua`).

## 0.1.1 (2026-03-01)

### Style

- style: tweak traffic lights size.

## 0.1.0 (2026-02-27)

### New Features

- feat: Initial release.
