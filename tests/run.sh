#!/usr/bin/env bash
set -euo pipefail

# Render check for the code-window filter.
#
# Each test renders one fixture and reads one fact off the rendered file.
# Quarto builds its extension registry before a pre-render script runs, and it
# does not follow symbolic links, so the extension is copied next to the
# fixtures rather than linked. docs/_scripts/sync-extension.sh solves the same
# problem for the documentation site.
#
# Usage: tests/run.sh

tests_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(dirname "${tests_dir}")"

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

cp -R "${repo_dir}/_extensions" "${work_dir}/_extensions"
cp "${tests_dir}"/fixtures/*.qmd "${work_dir}/"

passed=0
failed=0

# Report one test and count it.
# $1 outcome, "pass" or "fail". $2 name. $3 what the test expected.
report() {
	if [ "$1" = "pass" ]; then
		passed=$((passed + 1))
		printf 'pass  %s\n' "$2"
	else
		failed=$((failed + 1))
		printf 'FAIL  %s\n' "$2"
		printf '      expected %s\n' "$3"
	fi
}

# Render a fixture, and stop the run when the render itself fails.
# $1 fixture base name. $2 target format.
render() {
	if ! quarto render "${work_dir}/$1.qmd" --to "$2" --quiet >"${work_dir}/$1.log" 2>&1; then
		printf 'FAIL  %s: the render failed\n' "$1"
		tail -n 20 "${work_dir}/$1.log"
		exit 1
	fi
}

# Count the code-window calls in a rendered Typst file. The wrapper's own
# definition reads "#let code-window(", so a call is matched at the start of a
# line and with its first argument.
# $1 rendered file
count_typst_windows() {
	grep -c '^#code-window(filename' "$1" || true
}

# Answer the classes of every highlighted block in a rendered HTML file. The
# injected script names its marker classes in a selector, never in a tag, so
# reading the tags alone keeps the script out of the answer.
# $1 rendered file
block_classes() {
	grep -o '<pre class="[^"]*"' "$1" || true
}

# Answer the opening tag of every highlighted block's wrapper in a rendered
# HTML file. Pandoc writes an attribute the filter left behind onto this tag,
# as data-code-window-*. The injected script is left out for the same reason
# as above.
# $1 rendered file
block_wrappers() {
	grep -o '<div class="sourceCode"[^>]*>' "$1" || true
}

# ============================================================================
# The output of an executed cell keeps the shape Quarto gave it
# ============================================================================

for fixture in cell-output-bare cell-output-classed; do
	render "${fixture}" typst
	if [ "$(count_typst_windows "${work_dir}/${fixture}.typ")" -eq 0 ]; then
		report pass "${fixture}: the output of the cell is not framed"
	else
		report fail "${fixture}: the output of the cell is not framed" \
			"no code-window call in ${fixture}.typ"
	fi
done

# ============================================================================
# Inline code keeps the token definitions in a document with no code block
# ============================================================================

# The filter boxes inline code and leaves the element itself in place, so
# Pandoc highlights it and writes the token definitions. The render fails to
# compile when they are missing, and the grep says why.
render inline-code-only typst
if grep -q '^#let NormalTok(' "${work_dir}/inline-code-only.typ"; then
	report pass "inline-code-only: the token definitions reach the document"
else
	report fail "inline-code-only: the token definitions reach the document" \
		"a #let NormalTok( definition in inline-code-only.typ"
fi

# A theme with a background colour takes the box that names the colour.
if grep -q 'box(fill: rgb(' "${work_dir}/inline-code-only.typ"; then
	report pass "inline-code-only: the box takes the colour of the theme"
else
	report fail "inline-code-only: the box takes the colour of the theme" \
		"a box(fill: rgb( call in inline-code-only.typ"
fi

# A code block goes through the Skylighting override, and the inline code
# keeps its own box in the same document.
render inline-code-with-block typst
if grep -q '^#Skylighting(' "${work_dir}/inline-code-with-block.typ" &&
	grep -q 'box(fill: rgb(' "${work_dir}/inline-code-with-block.typ"; then
	report pass "inline-code-with-block: the block and the inline code share the document"
else
	report fail "inline-code-with-block: the block and the inline code share the document" \
		"a #Skylighting( call and a box(fill: rgb( call in inline-code-with-block.typ"
fi

# A theme that gives no background colour takes the other box, which mixes its
# colour from the page. The render compiles that box.
render inline-code-no-theme typst
if grep -q 'box(fill: color.mix' "${work_dir}/inline-code-no-theme.typ"; then
	report pass "inline-code-no-theme: the box takes its colour from the page"
else
	report fail "inline-code-no-theme: the box takes its colour from the page" \
		"a box(fill: color.mix call in inline-code-no-theme.typ"
fi

# ============================================================================
# A per-block style override reaches the output
# ============================================================================

render block-style-override html
if block_classes "${work_dir}/block-style-override.html" | grep -q 'cw-style-windows'; then
	report pass "block-style-override: the block carries the style marker"
else
	report fail "block-style-override: the block carries the style marker" \
		"a cw-style-windows class on the highlighted block"
fi

# The extension reports a schema it cannot read and renders the document all
# the same, so a per-block override has to survive that state too.
mv "${work_dir}/_extensions/code-window/_schema.yml" "${work_dir}/schema.yml.aside"
render block-style-override html
mv "${work_dir}/schema.yml.aside" "${work_dir}/_extensions/code-window/_schema.yml"

if block_classes "${work_dir}/block-style-override.html" | grep -q 'cw-style-windows'; then
	report pass "block-style-override: the style marker survives an unreadable schema"
else
	report fail "block-style-override: the style marker survives an unreadable schema" \
		"a cw-style-windows class on the highlighted block"
fi

# ============================================================================
# The filter's own attributes stay out of the rendered document
# ============================================================================

for fixture in disabled-block lines-label-off; do
	render "${fixture}" html
	if block_wrappers "${work_dir}/${fixture}.html" | grep -q 'data-code-window-'; then
		report fail "${fixture}: no code-window attribute reaches the output" \
			"no data-code-window- attribute on the wrapper"
	else
		report pass "${fixture}: no code-window attribute reaches the output"
	fi
done

# The label is the filter's own name for a block, and no reader of it exists on
# a format that draws no chrome, so neither the label nor the pass that writes
# it reaches the output.
render unsupported-format markdown
if grep -q 'code-window-auto-label' "${work_dir}/unsupported-format.md"; then
	report fail "unsupported-format: the internal label stays out of the output" \
		"no code-window-auto-label in unsupported-format.md"
else
	report pass "unsupported-format: the internal label stays out of the output"
fi

# ============================================================================
# A filter that draws no chrome leaves a block's language alone
# ============================================================================

# The pass that relabels a language serves the derived filename, and nothing
# derives a filename with the filter off.
render filter-disabled html
if block_classes "${work_dir}/filter-disabled.html" | grep -q 'foo'; then
	report pass "filter-disabled: the block keeps its own language"
else
	report fail "filter-disabled: the block keeps its own language" \
		"a foo class on the block"
fi

# The other branch of the same pass inserts a class where the block had none,
# which turns a bare block into a highlighted one.
render filter-disabled-no-language html
if block_classes "${work_dir}/filter-disabled-no-language.html" | grep -q 'default'; then
	report fail "filter-disabled-no-language: the block gains no class" \
		"no default class on the block"
else
	report pass "filter-disabled-no-language: the block gains no class"
fi

# A render with no derived name to build reads no label either, whatever the
# format, so the pass has no reader there.
render auto-filename-off html
if block_classes "${work_dir}/auto-filename-off.html" | grep -q 'foo'; then
	report pass "auto-filename-off: the block keeps its own language"
else
	report fail "auto-filename-off: the block keeps its own language" \
		"a foo class on the block"
fi

# The same pass serves no reader on a format that gets no chrome either.
if grep -q '^``` foo' "${work_dir}/unsupported-format.md"; then
	report pass "unsupported-format: the block keeps its own language"
else
	report fail "unsupported-format: the block keeps its own language" \
		"a fence reading \`\`\` foo in unsupported-format.md"
fi

# Where the chrome is drawn, the pass has work to do: the class becomes the one
# Pandoc has a theme for, the block is framed, and the title bar keeps the
# language the author wrote. Without this, the two tests above would stay green
# if the gate ever closed on a render it should let through.
render language-relabelled html
if block_classes "${work_dir}/language-relabelled.html" | grep -q 'default' &&
	block_classes "${work_dir}/language-relabelled.html" | grep -q 'cw-auto' &&
	block_wrappers "${work_dir}/language-relabelled.html" | grep -q 'data-filename="foo"'; then
	report pass "language-relabelled: the block is relabelled and framed"
else
	report fail "language-relabelled: the block is relabelled and framed" \
		"a default class, a cw-auto class, and data-filename=\"foo\" on the block"
fi

# ============================================================================
# The schema is where an option's default is written down
# ============================================================================

# The schema declares a default for every option, and so did a table in the
# Lua. Changing the schema alone has to change the render, or the two can
# disagree with nothing to say so. The wrapper name is the option under test
# because it reaches the Typst output word for word.
render wrapper-default typst
if grep -q '^#code-window(' "${work_dir}/wrapper-default.typ"; then
	report pass "wrapper-default: the schema default names the wrapper"
else
	report fail "wrapper-default: the schema default names the wrapper" \
		"a #code-window( call in wrapper-default.typ"
fi

sed -i.aside 's/default: "code-window"/default: "my-window"/' \
	"${work_dir}/_extensions/code-window/_schema.yml"
render wrapper-default typst
mv "${work_dir}/_extensions/code-window/_schema.yml.aside" \
	"${work_dir}/_extensions/code-window/_schema.yml"

# The old name has to be gone as well as the new one present, because a rename
# that missed a call site would leave both in the document.
if grep -q '^#my-window(' "${work_dir}/wrapper-default.typ" &&
	! grep -q '^#code-window(' "${work_dir}/wrapper-default.typ"; then
	report pass "wrapper-default: a default changed in the schema alone is followed"
else
	report fail "wrapper-default: a default changed in the schema alone is followed" \
		"a #my-window( call and no #code-window( call in wrapper-default.typ"
fi

# With no schema to read, the fallback in the Lua answers instead, and the
# document still renders rather than stopping.
mv "${work_dir}/_extensions/code-window/_schema.yml" "${work_dir}/schema.yml.aside"
render wrapper-default typst
mv "${work_dir}/schema.yml.aside" "${work_dir}/_extensions/code-window/_schema.yml"

if grep -q '^#code-window(' "${work_dir}/wrapper-default.typ"; then
	report pass "wrapper-default: the fallback answers when the schema cannot be read"
else
	report fail "wrapper-default: the fallback answers when the schema cannot be read" \
		"a #code-window( call in wrapper-default.typ"
fi

# ============================================================================
# A block opts out of the document's collapse setting
# ============================================================================

render collapse-block-off html

if block_classes "${work_dir}/collapse-block-off.html" | grep -q 'cw-collapse'; then
	report fail "collapse-block-off: the block opts out of collapsing" \
		"no cw-collapse class in collapse-block-off.html"
else
	report pass "collapse-block-off: the block opts out of collapsing"
fi

# ============================================================================

printf '\n%s passed, %s failed\n' "${passed}" "${failed}"
[ "${failed}" -eq 0 ]
