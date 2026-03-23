# Code Window Extension for Quarto

A Quarto extension that adds window-style decorations to code blocks.
Three styles are available: macOS traffic lights, Windows title bar buttons, or a plain filename bar.
Supports HTML, Reveal.js, and Typst formats.

## Installation

```bash
quarto add mcanouil/quarto-code-window@0.2.0
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
    hotfix:
      quarto-version: ~
      code-annotations: true
      skylighting: true
```

### Options

| Option          | Type    | Default         | Description                                                          |
| --------------- | ------- | --------------- | -------------------------------------------------------------------- |
| `enabled`       | boolean | `true`          | Enable or disable the code-window filter.                            |
| `auto-filename` | boolean | `true`          | Automatically generate filename labels from the code block language. |
| `style`         | string  | `"macos"`       | Window decoration style: `"macos"`, `"windows"`, or `"default"`.     |
| `wrapper`       | string  | `"code-window"` | Typst wrapper function name for code-window rendering.               |

### Hotfix Options

These options are **temporary** and will be removed in a future version (see [Temporary hot-fixes](#temporary-hot-fixes-typst)).

| Option                    | Type    | Default | Description                                                                                |
| ------------------------- | ------- | ------- | ------------------------------------------------------------------------------------------ |
| `hotfix.quarto-version`   | string  | _unset_ | Quarto version at or above which all hot-fixes are automatically disabled.                 |
| `hotfix.code-annotations` | boolean | `true`  | Enable the code-annotations hot-fix for Typst output.                                      |
| `hotfix.skylighting`      | boolean | `true`  | Enable the Skylighting hot-fix for Typst output (overrides block styling and inline code). |

### Styles

- **`"macos"`** (default): Traffic light buttons (red, yellow, green) on the left, filename on the right.
- **`"windows"`**: Minimise, maximise, and close buttons on the right, filename on the left.
- **`"default"`**: Plain filename on the left, no window decorations.

### Block-Level Style Override

Override the style for a single code block using the `code-window-style` attribute:

````markdown
```{.python filename="example.py" code-window-style="windows"}
print("Windows style for this block only")
```
````

### Temporary Hot-fixes (Typst)

The extension includes two temporary hot-fixes for Typst output that compensate for missing Quarto/Pandoc features.
Both will be removed once [quarto-dev/quarto-cli#14170](https://github.com/quarto-dev/quarto-cli/pull/14170) is released.
After that, the extension will focus solely on **auto-filename** and **code-window-style** features.

- **`hotfix.code-annotations`**: processes code annotation markers for Typst, since Quarto does not yet support `code-annotations` in Typst output.
  The `filename` attribute for code blocks will also become natively supported.
- **`hotfix.skylighting`**: overrides Pandoc's Skylighting output for Typst to fix block and inline code styling.

Set `hotfix.quarto-version` to automatically disable both hot-fixes once you update Quarto to the version that includes native support:

```yaml
extensions:
  code-window:
    hotfix:
      quarto-version: "1.10.0"
```

Future removal playbook:

1. Delete `hotfix` parsing from `code-window.lua` (`HOTFIX_DEFAULTS`, hotfix section in `Meta`).
2. Remove the `hotfix` section from `_schema.yml`.
3. Remove the skylighting guard and loader in `main.lua`.
4. Remove annotation processing from `code-window.lua`.
5. Delete `_modules/hotfix/` directory entirely.

## Example

Here is the source code for a minimal example: [example.qmd](example.qmd).

Rendered output:

- [HTML](https://m.canouil.dev/quarto-code-window/).
- [Typst](https://m.canouil.dev/quarto-code-window/example-typst.pdf).
- [Reveal.js](https://m.canouil.dev/quarto-code-window/example-revealjs.html).
