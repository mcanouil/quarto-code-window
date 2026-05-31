# Code Window Extension for Quarto

A Quarto extension that adds window-style decorations to code blocks.
Three styles are available: macOS traffic lights, Windows title bar buttons, or a plain filename bar.
Supports HTML, Reveal.js, and Typst formats.

## Installation

```bash
quarto add mcanouil/quarto-code-window@1.2.0
```

This will install the extension under the `_extensions` subdirectory.
If you are using version control, you will want to check in this directory.

## Usage

Add the filter to your document or project:

```yaml
filters:
  - at: pre-quarto
    path: code-window
```

### Explicit Filename

Code blocks with a `filename` attribute display a window header with the filename.
The decoration style depends on the `style` option.

````markdown
```{.python filename="fibonacci.py"}
def fibonacci(n: int) -> int:
    if n <= 1:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)
```
````

### Auto-Generated Filename

By default, code blocks without an explicit filename automatically show the language name in small-caps styling.

````markdown
```python
print("Hello, World!")
```
````

## Configuration

Configure the extension in your document's YAML front matter:

```yaml
extensions:
  code-window:
    enabled: true
    auto-filename: true
    style: "macos"
    wrapper: "code-window"
    collapse: false
    lines-label: true
    hotfix:
      code-annotations: true
      skylighting: true
      typst-title: true
```

### Options

| Option          | Type           | Default         | Description                                                                                              |
| --------------- | -------------- | --------------- | -------------------------------------------------------------------------------------------------------- |
| `enabled`       | boolean        | `true`          | Enable or disable the code-window filter.                                                                |
| `auto-filename` | boolean        | `true`          | Automatically generate filename labels from the code block language. Set to `false` to disable globally. |
| `style`         | string         | `"macos"`       | Window decoration style: `"macos"`, `"windows"`, or `"default"`.                                         |
| `wrapper`       | string         | `"code-window"` | Typst wrapper function name for code-window rendering.                                                   |
| `collapse`      | boolean/string | `false`         | Wrap every code window in a `<details>` element (HTML). Accepts `false`, `true`, `"open"`, `"closed"`.   |
| `lines-label`   | boolean        | `true`          | Render a small chip next to the filename showing the highlighted-line spec.                              |

### Hotfix Options

These options are **temporary** and will be removed in a future version (see [Temporary hot-fixes](#temporary-hot-fixes-typst)).

Each hotfix value can be a simple boolean or a map with `enabled` and `quarto-version` keys for per-hotfix version thresholds.

| Option                    | Type         | Default | Description                                                                                |
| ------------------------- | ------------ | ------- | ------------------------------------------------------------------------------------------ |
| `hotfix.code-annotations` | boolean/map  | `true`  | Enable the code-annotations hot-fix for Typst output.                                      |
| `hotfix.skylighting`      | boolean/map  | `true`  | Enable the Skylighting hot-fix for Typst output (overrides block styling and inline code). |
| `hotfix.typst-title`      | boolean/map  | `true`  | Enable the Typst title hot-fix (evaluates theorem title strings as markup).                |

### Styles

- **`"macos"`** (default): Traffic light buttons (red, yellow, green) on the left, filename on the right.
- **`"windows"`**: Minimise, maximise, and close buttons on the right, filename on the left.
- **`"default"`**: Plain filename on the left, no window decorations.

### Block-Level Attributes

Override the style or toggle features for a single code block:

| Attribute                      | Type           | Default | Description                                                                                                          |
| ------------------------------ | -------------- | ------- | -------------------------------------------------------------------------------------------------------------------- |
| `code-window-style`            | string         |         | Override the global style for this block: `"macos"`, `"windows"`, or `"default"`.                                    |
| `code-window-enabled`          | boolean        | `true`  | Set to `false` to disable window chrome while keeping annotations.                                                   |
| `code-window-no-auto-filename` | boolean        | `false` | Suppress the auto-generated filename for this block.                                                                 |
| `code-window-collapse`         | boolean/string |         | Render this code block inside a `<details>` element (HTML). Accepts `true` (closed), `false`, `"open"`, `"closed"`.  |
| `code-window-lines`            | string         |         | Highlighted-lines spec rendered as a chip alongside the filename (e.g. `"1,3-5"`). Falls back to `code-line-numbers`. |

````markdown
```{.python filename="example.py" code-window-style="windows"}
print("Windows style for this block only")
```
````

### Highlighted Lines Chip

When a code block carries Quarto's `code-line-numbers` attribute with a line specification (e.g. `"1,3-5"`), the spec is rendered as a small chip beside the filename in the title bar.

````markdown
```{.python filename="loader.py" code-line-numbers="1,4-5"}
import pandas as pd

def load(path):
    df = pd.read_csv(path)
    return df.dropna()
```
````

Override the displayed text with `code-window-lines="..."` or disable the chip globally with `lines-label: false`.

### Collapsible Code Windows (HTML)

Set `code-window-collapse` on a block, or `collapse` at the document level, to wrap the code window in a `<details>` element.
The title bar becomes the `<summary>`.

````markdown
```{.python filename="long.py" code-window-collapse="closed"}
# Long block hidden behind a clickable title bar.
print("Click the title bar to expand.")
```
````

This feature applies to HTML and Reveal.js output only.

### Customising Window-Button Icons (HTML)

The macOS and Windows window-button icons are exposed as CSS custom properties so you can override them in your own stylesheet:

```css
:root {
  --code-window-macos-icon: url("data:image/svg+xml,...");
  --code-window-windows-icon: url("data:image/svg+xml,...");
  --code-window-macos-icon-width: 3.4em;
  --code-window-windows-icon-width: 3.6em;
  --code-window-icon-height: 0.85em;
}
```

### Temporary Hot-fixes (Typst)

The extension includes three temporary hot-fixes for Typst output that compensate for missing Quarto/Pandoc features.
All three will be removed once [quarto-dev/quarto-cli#14170](https://github.com/quarto-dev/quarto-cli/pull/14170) is released.
After that, the extension will focus solely on **auto-filename** and **code-window-style** features.

- **`hotfix.code-annotations`**: processes code annotation markers for Typst, since Quarto does not yet support `code-annotations` in Typst output.
  The `filename` attribute for code blocks will also become natively supported.
- **`hotfix.skylighting`**: overrides Pandoc's Skylighting output for Typst to fix block and inline code styling.
- **`hotfix.typst-title`**: evaluates theorem title strings as Typst markup so that inline formatting (e.g., code) renders correctly.

Each hotfix accepts either a boolean or a map with `enabled` and `quarto-version` keys for per-hotfix version thresholds (upstream fixes may land in different Quarto releases):

```yaml
extensions:
  code-window:
    hotfix:
      code-annotations: true
      skylighting:
        enabled: false
      typst-title:
        quarto-version: "1.10.0"
```

Future removal playbook:

1. Delete `hotfix` parsing from `code-window.lua` (`HOTFIX_DEFAULTS`, hotfix section in `Meta`).
2. Remove the `hotfix` section from `_schema.yml`.
3. Remove the skylighting guard and loader in `main.lua`.
4. Remove annotation processing from `code-window.lua`.
5. Remove the typst-title fix filter and metadata bridge.
6. Delete `_modules/hotfix/` directory entirely.

## Example

Here is the source code for a minimal example: [example.qmd](example.qmd).

Rendered output:

- [HTML](https://m.canouil.dev/quarto-code-window/).
- [Typst](https://m.canouil.dev/quarto-code-window/example-typst.pdf).
- [Reveal.js](https://m.canouil.dev/quarto-code-window/example-revealjs.html).
