# Code Window Extension for Quarto

A Quarto extension that adds window-style decorations to code blocks.
Three styles are available: macOS traffic lights, Windows title bar buttons, or a plain filename bar.
Supports HTML, Reveal.js, and Typst formats.

## Installation

```bash
quarto add mcanouil/quarto-code-window@0.1.1
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
    skylighting-fix: true
```

### Options

| Option            | Type    | Default         | Description                                                                         |
| ----------------- | ------- | --------------- | ----------------------------------------------------------------------------------- |
| `enabled`         | boolean | `true`          | Enable or disable the code-window filter.                                           |
| `auto-filename`   | boolean | `true`          | Automatically generate filename labels from the code block language.                |
| `style`           | string  | `"macos"`       | Window decoration style: `"macos"`, `"windows"`, or `"default"`.                    |
| `wrapper`         | string  | `"code-window"` | Typst wrapper function name for code-window rendering.                              |
| `skylighting-fix` | boolean | `true`          | Enable or disable the Skylighting hot-fix for Typst output (block and inline code). |

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

### Typst Skylighting Hot-fix (Integrated)

`code-window` loads its Typst skylighting hot-fix internally from `_extensions/code-window/skylighting-typst-fix.lua`, so no second filter entry is required.
Set `skylighting-fix: false` to disable the hot-fix without removing the file.

This keeps the hot-fix separated from `code-window.lua` for easy future removal while preserving combined behaviour.

Future removal playbook:

1. Remove the skylighting loader call in `_extensions/code-window/code-window.lua`.
2. Delete `_extensions/code-window/skylighting-typst-fix.lua`.

## Example

Here is the source code for a minimal example: [example.qmd](example.qmd).

Rendered output:

- [HTML](https://m.canouil.dev/quarto-code-window/).
- [Typst](https://m.canouil.dev/quarto-code-window/example-typst.pdf).
- [Reveal.js](https://m.canouil.dev/quarto-code-window/example-revealjs.html).
