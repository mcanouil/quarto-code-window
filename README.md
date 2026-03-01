# Code Window Extension for Quarto

A Quarto extension that styles code blocks as macOS-style windows with traffic light buttons and a filename bar.
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

Code blocks with a `filename` attribute display a window header with traffic light buttons and the filename right-aligned.

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
    wrapper: "code-window"
```

### Options

| Option          | Type    | Default         | Description                                                          |
| --------------- | ------- | --------------- | -------------------------------------------------------------------- |
| `enabled`       | boolean | `true`          | Enable or disable the code-window filter.                            |
| `auto-filename` | boolean | `true`          | Automatically generate filename labels from the code block language. |
| `wrapper`       | string  | `"code-window"` | Typst wrapper function name for code-window rendering.               |

### Typst Skylighting Hot-fix (Integrated)

`code-window` loads its Typst skylighting hot-fix internally from `_extensions/code-window/skylighting-typst-fix.lua`, so no second filter entry is required.

This keeps the hot-fix separated from `code-window.lua` for easy future removal while preserving combined behavior.

Future removal playbook:

1. Remove the skylighting loader call in `_extensions/code-window/code-window.lua`.
2. Delete `_extensions/code-window/skylighting-typst-fix.lua`.

## Example

Here is the source code for a minimal example: [example.qmd](example.qmd).

Rendered output:

- [HTML](https://m.canouil.dev/quarto-code-window/).
- [Typst](https://m.canouil.dev/quarto-code-window/example-typst.pdf).
- [Reveal.js](https://m.canouil.dev/quarto-code-window/example-revealjs.html).
