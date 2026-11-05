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
# Requires: quarto, and pdftotext from poppler for the page-break test.
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

# Succeed when one page of page-break-title.txt holds both strings. pdftotext
# ends each page with a form feed, so awk reads one page per record.
# $1 first string. $2 second string.
same_page() {
	awk -v RS='\f' -v first="$1" -v second="$2" \
		'index($0, first) && index($0, second) { found = 1 } END { exit !found }' \
		"${work_dir}/page-break-title.txt"
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
# The Typst hot-fix stands down with the filter
# ============================================================================

# The hot-fix contributes two passes, and both write Typst that only the
# filter's own preamble declares. That preamble is not written with the filter
# off, so both passes have to stand down there. The block pass is caught by the
# "_cw-" prefix the colour helpers and the annotation state share. The inline
# pass takes a different shape where the theme gives a background colour, and
# names no helper at all, so the box itself is the thing to look for.
for fixture in filter-disabled filter-disabled-no-language; do
	render "${fixture}" typst

	# Both assertions below are negative, and a missing file would answer them
	# the same way a clean render does. So the file is checked for first.
	if [ -f "${work_dir}/${fixture}.typ" ]; then
		report pass "${fixture}: the render keeps its Typst source"
	else
		report fail "${fixture}: the render keeps its Typst source" \
			"a ${fixture}.typ in the work directory"
		continue
	fi

	if grep -q '_cw-' "${work_dir}/${fixture}.typ"; then
		report fail "${fixture}: the block pass stands down with the filter" \
			"no _cw- helper call in ${fixture}.typ"
	else
		report pass "${fixture}: the block pass stands down with the filter"
	fi

	if grep -q 'box(fill: rgb(' "${work_dir}/${fixture}.typ"; then
		report fail "${fixture}: the inline pass stands down with the filter" \
			"no box(fill: rgb( call in ${fixture}.typ"
	else
		report pass "${fixture}: the inline pass stands down with the filter"
	fi
done

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

# The script folds a block that carries no marker, reading the absence as
# "this block said nothing", so the opt-out is a marker of its own rather
# than a missing one. The second block is here to show the two differ.
collapse_markers="$(block_classes "${work_dir}/collapse-block-off.html" | grep -o 'cw-collapse-[a-z]*' | sort | tr '\n' ' ')"

if [ "${collapse_markers}" = "cw-collapse-closed cw-collapse-none " ]; then
	report pass "collapse-block-off: the block opts out and its neighbour does not"
else
	report fail "collapse-block-off: the block opts out and its neighbour does not" \
		"cw-collapse-none on one block and cw-collapse-closed on the other, got: ${collapse_markers}"
fi

# The document setting still reaches the page, which is what the opt-out has
# to override.
if grep -q 'DEFAULT_COLLAPSE="closed"' "${work_dir}/collapse-block-off.html"; then
	report pass "collapse-block-off: the document setting reaches the page"
else
	report fail "collapse-block-off: the document setting reaches the page" \
		'DEFAULT_COLLAPSE="closed" in collapse-block-off.html'
fi

# ============================================================================
# Inline code in the document title is left to Quarto
# ============================================================================

# The title is metadata, written into the template call before the
# extension's own definitions, so the inline code pass must not box it. The
# render compiling is the check; the grep says what reached the title.
render title-inline-code typst
# shellcheck disable=SC2016 # the backticks are a literal Typst code span, not a command
if grep -q 'title: \[A #raw("code") title\]\|title: \[A `code` title\]' "${work_dir}/title-inline-code.typ"; then
	report pass "title-inline-code: the title code is not boxed"
else
	report fail "title-inline-code: the title code is not boxed" \
		"an unboxed code span in the title argument of title-inline-code.typ"
fi

# ============================================================================
# A theorem title renders as Typst content without a hot-fix
# ============================================================================

# Quarto writes the title as content since 1.10, so the markup survives and
# the extension adds no wrapper of its own. Inline code in the title still has
# to compile, which the render itself checks.
render theorem-title typst
if grep -qF '#theorem(title: [A title with #emph[emphasis]' "${work_dir}/theorem-title.typ"; then
	report pass "theorem-title: the title keeps its markup"
else
	report fail "theorem-title: the title keeps its markup" \
		"#theorem(title: [A title with #emph[emphasis] in theorem-title.typ"
fi
if grep -q 'hot-fix for Quarto rendering theorem titles' "${work_dir}/theorem-title.typ"; then
	report fail "theorem-title: no title hot-fix is injected" \
		"no 'hot-fix for Quarto rendering theorem titles' block in theorem-title.typ"
else
	report pass "theorem-title: no title hot-fix is injected"
fi

# Inline code in the title takes the same box as inline code anywhere else.
if grep -F '#theorem(title: [A title with #emph[emphasis]' "${work_dir}/theorem-title.typ" | grep -q 'box(fill:'; then
	report pass "theorem-title: inline code in the title is boxed"
else
	report fail "theorem-title: inline code in the title is boxed" \
		"a box(fill: call inside the #theorem(title: [...]) line of theorem-title.typ"
fi

# ============================================================================
# A title bar never sits alone at the bottom of a page
# ============================================================================

# Each window in the fixture starts where the title bar fits on the page but
# the first line of code does not. The title bar has to move to the next page
# with its code. The plain window and the annotated window take different
# content paths in the wrapper, so both are checked. The test reads the page
# text of the PDF, so it needs pdftotext from poppler.
if command -v pdftotext >/dev/null 2>&1; then
	render page-break-title typst
	pdftotext "${work_dir}/page-break-title.pdf" "${work_dir}/page-break-title.txt"

	for window in plain annotated; do
		if same_page "${window}.py" "${window}_first = 1"; then
			report pass "page-break-title: the ${window} title bar stays with its code"
		else
			report fail "page-break-title: the ${window} title bar stays with its code" \
				"${window}.py and ${window}_first = 1 on the same page of page-break-title.pdf"
		fi
	done

	# A window taller than a page has to start on the page where it is placed
	# and break across pages. The sticky title bar must not push it whole to
	# the next page and leave a near-empty page behind.
	if same_page "Text above the tall window." "tall_0 = 0"; then
		report pass "page-break-title: a window taller than a page starts on the current page"
	else
		report fail "page-break-title: a window taller than a page starts on the current page" \
			"the text above tall.py and tall_0 = 0 on the same page of page-break-title.pdf"
	fi

	# Without the sticky title bar, the same fixture has to leave the title bar
	# alone on its page. This proves that the fixture still forces the break,
	# so the checks above test the fix and not a layout that fits anyway.
	lua_file="${work_dir}/_extensions/code-window/code-window.lua"
	sed -i.aside '/sticky: true,/d' "${lua_file}"
	render page-break-title typst
	mv "${lua_file}.aside" "${lua_file}"
	pdftotext "${work_dir}/page-break-title.pdf" "${work_dir}/page-break-title.txt"

	for window in plain annotated; do
		if same_page "${window}.py" "${window}_first = 1"; then
			report fail "page-break-title: the fixture orphans the ${window} title bar without the fix" \
				"${window}.py and ${window}_first = 1 on different pages without sticky: true"
		else
			report pass "page-break-title: the fixture orphans the ${window} title bar without the fix"
		fi
	done
else
	report fail "page-break-title: the page text can be read" \
		"pdftotext on PATH (brew install poppler)"
fi

# ============================================================================
# A label set on a block asks for a window of its own
# ============================================================================

# Another filter sets code-window-auto-label to get a window with a derived
# style on a block that names no file. The label has to work when the document
# derives no names, and an explicit filename or a per-block opt-out still wins.
render auto-label-forced html
forced_html="${work_dir}/auto-label-forced.html"
forced_labels="$(block_wrappers "${forced_html}" | grep -c 'data-filename="Terminal"' || true)"
forced_auto="$(block_classes "${forced_html}" | grep -c 'cw-auto' || true)"
if [ "${forced_labels}" -eq 1 ] && [ "${forced_auto}" -eq 2 ] &&
	grep -q 'data-filename="run.sh"' "${forced_html}"; then
	report pass "auto-label-forced: only the labelled block takes the label in HTML"
else
	report fail "auto-label-forced: only the labelled block takes the label in HTML" \
		"one data-filename=\"Terminal\", two cw-auto blocks, and data-filename=\"run.sh\", got ${forced_labels} and ${forced_auto}"
fi

render auto-label-forced typst
forced_typst="${work_dir}/auto-label-forced.typ"
if [ "$(count_typst_windows "${forced_typst}")" -eq 3 ] &&
	grep -q '^#code-window(filename: "Terminal", is-auto: true' "${forced_typst}" &&
	grep -q '^#code-window(filename: "run.sh", is-auto: false' "${forced_typst}"; then
	report pass "auto-label-forced: only the labelled block takes the label in Typst"
else
	report fail "auto-label-forced: only the labelled block takes the label in Typst" \
		"three code-window calls, with one for Terminal with is-auto: true and one for run.sh"
fi

# The language pass runs for a labelled block and keeps its label, or the
# label would read "foo".
if block_wrappers "${forced_html}" | grep -q 'data-filename="Shell"'; then
	report pass "auto-label-forced: a labelled block in an unknown language is framed"
else
	report fail "auto-label-forced: a labelled block in an unknown language is framed" \
		"data-filename=\"Shell\" on a sourceCode wrapper in auto-label-forced.html"
fi

# A labelled block that refuses the window has no reader for the label, so the
# language pass leaves its language alone.
opted_out="$(block_classes "${forced_html}" | grep -c '"foo' || true)"
if [ "${opted_out}" -eq 2 ]; then
	report pass "auto-label-forced: a labelled block that refuses the window keeps its language"
else
	report fail "auto-label-forced: a labelled block that refuses the window keeps its language" \
		"two blocks with a foo class in auto-label-forced.html, got ${opted_out}"
fi

# ============================================================================
# The language is the first class Pandoc can highlight
# ============================================================================

render language-not-first html
not_first_html="${work_dir}/language-not-first.html"
named_bash="$(block_wrappers "${not_first_html}" | grep -c 'data-filename="bash"' || true)"
if [ "${named_bash}" -eq 2 ] &&
	! block_classes "${not_first_html}" | grep -q 'default bash'; then
	report pass "language-not-first: a later language class names and highlights the block"
else
	report fail "language-not-first: a later language class names and highlights the block" \
		"two wrappers with data-filename=\"bash\" and no default class before bash, got ${named_bash}"
fi

if block_wrappers "${not_first_html}" | grep -q 'data-filename="default"' &&
	[ "$(block_classes "${not_first_html}" | grep -c 'numberLines')" -eq 2 ]; then
	report pass "language-not-first: a numbered block with no language keeps its numbers"
else
	report fail "language-not-first: a numbered block with no language keeps its numbers" \
		"a numberLines class on both numbered blocks, and data-filename=\"default\" on one"
fi

render language-not-first typst
not_first_typ="${work_dir}/language-not-first.typ"
if [ "$(grep -c '^#code-window(filename: "bash"' "${not_first_typ}" || true)" -eq 2 ] &&
	[ "$(grep -c '^#code-window(filename: "default"' "${not_first_typ}" || true)" -eq 1 ]; then
	report pass "language-not-first: the Typst windows are named after the language"
else
	report fail "language-not-first: the Typst windows are named after the language" \
		"two windows named bash and one named default in language-not-first.typ"
fi

# ============================================================================

printf '\n%s passed, %s failed\n' "${passed}" "${failed}"
[ "${failed}" -eq 0 ]
