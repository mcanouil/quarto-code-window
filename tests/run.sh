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
# Requires: quarto, R with knitr for the executed-cell test, and pdftotext
# from poppler for the page-break and theme inset tests.
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

# Render a fixture, and stop the run when the render itself fails. A fixture
# is a file, or a directory that holds a project.
# $1 fixture base name. $2 target format.
render() {
	local target="${work_dir}/$1.qmd"
	if [ -d "${work_dir}/$1" ]; then
		target="${work_dir}/$1"
	fi
	if ! quarto render "${target}" --to "$2" --quiet >"${work_dir}/$1.log" 2>&1; then
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

# Compile a rendered Typst file to SVG, and stop the run when the compile
# fails.
# $1 base name of the .typ file in the work directory.
compile_svg() {
	if ! quarto typst compile "${work_dir}/$1.typ" "${work_dir}/$1.svg" \
		>"${work_dir}/$1-svg.log" 2>&1; then
		printf 'FAIL  %s: the SVG compile failed\n' "$1"
		tail -n 20 "${work_dir}/$1-svg.log"
		exit 1
	fi
}

# Count the matches of a fixed string in a file, and answer 0 when none match.
# $1 file. $2 fixed string.
count_in() {
	grep -o -F "$2" "$1" | wc -l | tr -d ' ' || true
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

# Count the windows in a rendered HTML file that hold a derived filename.
# $1 rendered file
count_auto_windows() {
	grep -c '<div class="code-with-filename code-window-auto">' "$1" || true
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
if block_classes "${work_dir}/language-relabelled.html" | grep -q 'default foo' &&
	[ "$(count_auto_windows "${work_dir}/language-relabelled.html")" -eq 1 ] &&
	block_wrappers "${work_dir}/language-relabelled.html" | grep -q 'data-filename="foo"'; then
	report pass "language-relabelled: the block is relabelled and framed"
else
	report fail "language-relabelled: the block is relabelled and framed" \
		"a default class before the foo class, a code-window-auto wrapper, and data-filename=\"foo\" on the block"
fi

# A block that refuses a title inside a render that draws chrome has no reader
# for the label either, so it keeps its class. The last two blocks still get a
# title, from the language or from the filename, which shows the gate is per
# block and not for the whole render.
render language-refused html
refused_classes="$(block_classes "${work_dir}/language-refused.html")"
if [ "$(printf '%s\n' "${refused_classes}" | grep -c '^<pre class="foo"$')" -eq 2 ] &&
	[ "$(printf '%s\n' "${refused_classes}" | grep -c 'default foo')" -eq 2 ]; then
	report pass "language-refused: a block with no title keeps its class"
else
	report fail "language-refused: a block with no title keeps its class" \
		"two <pre class=\"foo\"> and two default foo, got: ${refused_classes}"
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
# The hot-fix defaults come from the schema
# ============================================================================

# Each case is a project of its own, with its own copy of the extension, so a
# change to one schema reaches no other test. The document sets no hot-fix.
# $1 case name.
hotfix_project() {
	local dir="${work_dir}/hotfix-$1"
	mkdir -p "${dir}"
	cp -R "${repo_dir}/_extensions" "${dir}/_extensions"
	cp "${tests_dir}/fixtures/hotfix-default.qmd" "${dir}/"
	printf 'project:\n  type: default\n' >"${dir}/_quarto.yml"
}

# With the skylighting default turned off in the schema alone, the render
# follows the schema and writes no Skylighting override.
hotfix_project schema-off
awk '/^      skylighting:$/ { found = 1 } found && /default: true/ { sub(/true/, "false"); found = 0 } { print }' \
	"${repo_dir}/_extensions/code-window/_schema.yml" \
	>"${work_dir}/hotfix-schema-off/_extensions/code-window/_schema.yml"
render hotfix-schema-off typst
if ! grep -q '// skylighting-typst-fix override' "${work_dir}/hotfix-schema-off/hotfix-default.typ"; then
	report pass "hotfix-schema-off: a hot-fix default changed in the schema alone is followed"
else
	report fail "hotfix-schema-off: a hot-fix default changed in the schema alone is followed" \
		"no Skylighting override in hotfix-schema-off/hotfix-default.typ"
fi

# The schema may also give a hot-fix default in the map form, which is read
# like the same map written in the document.
hotfix_project schema-map
awk '/^      skylighting:$/ { found = 1 } found && /default: true/ { sub(/true/, "{enabled: false}"); found = 0 } { print }' \
	"${repo_dir}/_extensions/code-window/_schema.yml" \
	>"${work_dir}/hotfix-schema-map/_extensions/code-window/_schema.yml"
render hotfix-schema-map typst
if ! grep -q '// skylighting-typst-fix override' "${work_dir}/hotfix-schema-map/hotfix-default.typ"; then
	report pass "hotfix-schema-map: a hot-fix default in the map form is followed"
else
	report fail "hotfix-schema-map: a hot-fix default in the map form is followed" \
		"no Skylighting override in hotfix-schema-map/hotfix-default.typ"
fi

# A value that is neither a boolean nor a map, such as a list, is read as
# text, so a list holding false turns the hot-fix off as before.
sed 's/^    keep-typ: true$/    keep-typ: true\
extensions:\
  code-window:\
    hotfix:\
      skylighting: [false]/' \
	"${work_dir}/hotfix-default.qmd" >"${work_dir}/hotfix-list.qmd"
render hotfix-list typst
if ! grep -q '// skylighting-typst-fix override' "${work_dir}/hotfix-list.typ"; then
	report pass "hotfix-list: a list value is read as text, not as a map"
else
	report fail "hotfix-list: a list value is read as text, not as a map" \
		"no Skylighting override in hotfix-list.typ"
fi

# A map with a quarto-version turns the hot-fix off from that version on. The
# first case names a version every Quarto has reached, the second one that no
# Quarto has, so the hot-fix is off and on in turn.
for threshold in 0.0.1 9999.0.0; do
	sed 's/^    keep-typ: true$/    keep-typ: true\
extensions:\
  code-window:\
    hotfix:\
      skylighting:\
        quarto-version: "'"${threshold}"'"/' \
		"${work_dir}/hotfix-default.qmd" >"${work_dir}/hotfix-version-${threshold}.qmd"
	render "hotfix-version-${threshold}" typst
done
if ! grep -q '// skylighting-typst-fix override' "${work_dir}/hotfix-version-0.0.1.typ" &&
	grep -q '// skylighting-typst-fix override' "${work_dir}/hotfix-version-9999.0.0.typ"; then
	report pass "hotfix-version: the hot-fix is off from its quarto-version on"
else
	report fail "hotfix-version: the hot-fix is off from its quarto-version on" \
		"no Skylighting override with 0.0.1, and one with 9999.0.0"
fi

# Without a schema to read, the extension falls back to its own defaults, so
# the hot-fix stays on.
hotfix_project schema-missing
rm "${work_dir}/hotfix-schema-missing/_extensions/code-window/_schema.yml"
render hotfix-schema-missing typst
if grep -q '// skylighting-typst-fix override' "${work_dir}/hotfix-schema-missing/hotfix-default.typ"; then
	report pass "hotfix-schema-missing: the hot-fix defaults fall back without a schema"
else
	report fail "hotfix-schema-missing: the hot-fix defaults fall back without a schema" \
		"a Skylighting override in hotfix-schema-missing/hotfix-default.typ"
fi

# ============================================================================
# A Typst template styles the window through the theme state
# ============================================================================

# The theme changes how the window is drawn, not the Typst source, so the
# source is compiled to SVG and the drawing is read there. The stock window
# draws a solid border mixed from the page colour, so a red dashed border can
# only come from the theme.
render typst-theme typst
compile_svg typst-theme
if grep -q 'stroke="#ff0000"' "${work_dir}/typst-theme.svg" &&
	grep -q 'stroke-dasharray' "${work_dir}/typst-theme.svg"; then
	report pass "typst-theme: the window draws the border the theme sets"
else
	report fail "typst-theme: the window draws the border the theme sets" \
		'a stroke="#ff0000" with a stroke-dasharray in typst-theme.svg'
fi

# The code in the window starts further right than the code of the block with
# no window, by most of the theme's 40pt inset. The block with no window comes
# after the window, so this also shows that the inset is reset there.
if command -v pdftotext >/dev/null 2>&1; then
	pdftotext -bbox "${work_dir}/typst-theme.pdf" "${work_dir}/typst-theme.html"
	x_in="$(grep -o 'xMin="[0-9.]*"[^>]*>x<' "${work_dir}/typst-theme.html" | grep -o '[0-9.]*' | head -n 1)"
	x_out="$(grep -o 'xMin="[0-9.]*"[^>]*>y<' "${work_dir}/typst-theme.html" | grep -o '[0-9.]*' | head -n 1)"
	if awk -v a="${x_in:-0}" -v b="${x_out:-0}" 'BEGIN { exit !(b > 0 && a - b > 25) }'; then
		report pass "typst-theme: the code in the window takes the theme's inset"
	else
		report fail "typst-theme: the code in the window takes the theme's inset" \
			"the code in the window more than 25pt right of the code outside, got ${x_in:-none} and ${x_out:-none}"
	fi
else
	report fail "typst-theme: the code in the window takes the theme's inset" \
		"pdftotext on PATH (brew install poppler)"
fi

# A misspelt key would otherwise be ignored without a word, so the compile
# stops and names the key. The themed source above is reused with one key
# misspelt, which tests the same check without a second render.
sed 's/border: rgb/boarder: rgb/' "${work_dir}/typst-theme.typ" \
	>"${work_dir}/typst-theme-unknown-key.typ"
if quarto typst compile "${work_dir}/typst-theme-unknown-key.typ" \
	>"${work_dir}/typst-theme-unknown-key.log" 2>&1; then
	report fail "typst-theme: an unknown key stops the compile" \
		"a failed compile of typst-theme-unknown-key.typ"
elif grep -q 'unknown key "boarder"' "${work_dir}/typst-theme-unknown-key.log"; then
	report pass "typst-theme: an unknown key stops the compile"
else
	report fail "typst-theme: an unknown key stops the compile" \
		"the key boarder named in typst-theme-unknown-key.log"
fi

# The theme's fill replaces the background of every highlighted block, in the
# window and out of it, and its stroke replaces the frame of the window. The
# themed source above is reused with the dashed border swapped for a fill and
# a stroke that draws only a blue top rule, so the red border colour stays only
# on the line below the title bar.
sed 's/stroke-dash: "dashed",/fill: rgb("#00ff00"), stroke: (top: 3pt + rgb("#0000ff"), rest: none),/' \
	"${work_dir}/typst-theme.typ" >"${work_dir}/typst-theme-fill-stroke.typ"
compile_svg typst-theme-fill-stroke
fill_stroke_svg="${work_dir}/typst-theme-fill-stroke.svg"
green_fills="$(count_in "${fill_stroke_svg}" 'fill="#00ff00"')"
if [ "${green_fills}" -eq 2 ]; then
	report pass "typst-theme-fill-stroke: both code blocks take the theme's fill"
else
	report fail "typst-theme-fill-stroke: both code blocks take the theme's fill" \
		"two fill=\"#00ff00\" in typst-theme-fill-stroke.svg, got ${green_fills}"
fi

# Typst draws a stroke that covers only some sides as filled shapes, so the top
# rule and the line below the title bar are fills. A full red frame would be a
# red stroke.
blue_sides="$(count_in "${fill_stroke_svg}" 'fill="#0000ff"')"
red_sides="$(count_in "${fill_stroke_svg}" 'fill="#ff0000"')"
red_frames="$(count_in "${fill_stroke_svg}" 'stroke="#ff0000"')"
if [ "${blue_sides}" -eq 1 ] && [ "${red_sides}" -eq 1 ] && [ "${red_frames}" -eq 0 ]; then
	report pass "typst-theme-fill-stroke: the window draws only the sides the theme sets"
else
	report fail "typst-theme-fill-stroke: the window draws only the sides the theme sets" \
		"one blue side, one red side, and no red frame, got ${blue_sides}, ${red_sides}, and ${red_frames}"
fi

# The highlighted block draws its own thin frame in the mixed border colour,
# which Typst writes as an oklab stroke. In the window the theme's stroke is the
# only edge, so only the block outside the window keeps that frame.
block_frames="$(count_in "${fill_stroke_svg}" 'stroke="oklab(')"
if [ "${block_frames}" -eq 1 ]; then
	report pass "typst-theme-fill-stroke: the code in the window has no frame of its own"
else
	report fail "typst-theme-fill-stroke: the code in the window has no frame of its own" \
		"one oklab stroke in typst-theme-fill-stroke.svg, got ${block_frames}"
fi

# With fill left at auto, both code blocks keep the highlight style's
# background. With fill set to none, neither block has one. The background is
# read from the override's fallback, so the test follows the highlight style.
sed 's/stroke-dash: "dashed",/fill: none,/' \
	"${work_dir}/typst-theme.typ" >"${work_dir}/typst-theme-fill-none.typ"
compile_svg typst-theme-fill-none
style_bg="$(sed -n 's/.*else { rgb("\(#[0-9a-f]*\)") }.*/\1/p' "${work_dir}/typst-theme.typ")"
style_fills_auto="$(count_in "${work_dir}/typst-theme.svg" "fill=\"${style_bg}\"")"
style_fills_none="$(count_in "${work_dir}/typst-theme-fill-none.svg" "fill=\"${style_bg}\"")"
if [ "${style_fills_auto}" -eq 2 ] && [ "${style_fills_none}" -eq 0 ]; then
	report pass "typst-theme-fill-none: fill none removes the background that auto keeps"
else
	report fail "typst-theme-fill-none: fill none removes the background that auto keeps" \
		"two fill=\"${style_bg}\" with auto and none with fill none, got ${style_fills_auto} and ${style_fills_none}"
fi

# With native Typst highlighting there is no Skylighting override, so the
# theme's fill reaches only the code in the window, through its raw rule.
sed -e 's/stroke-dash: "dashed",/fill: rgb("#00ff00"),/' \
	-e 's/^    keep-typ: true$/    keep-typ: true\
    syntax-highlighting: idiomatic/' \
	"${work_dir}/typst-theme.qmd" >"${work_dir}/typst-theme-fill-native.qmd"
render typst-theme-fill-native typst
compile_svg typst-theme-fill-native
native_fills="$(count_in "${work_dir}/typst-theme-fill-native.svg" 'fill="#00ff00"')"
if [ "${native_fills}" -eq 1 ]; then
	report pass "typst-theme-fill-native: only the code in the window takes the theme's fill"
else
	report fail "typst-theme-fill-native: only the code in the window takes the theme's fill" \
		"one fill=\"#00ff00\" in typst-theme-fill-native.svg, got ${native_fills}"
fi

# ============================================================================
# A wrapper that the document defines replaces the stock one
# ============================================================================

# The extension skips its own wrapper but still writes the helpers, which the
# Skylighting hot-fix calls. Without them the render fails to compile, so the
# render itself is the first check.
render wrapper-own typst
if [ "$(grep -c '^#let my-window(' "${work_dir}/wrapper-own.typ")" -eq 1 ] &&
	grep -q '^#let _cw-page-bg(' "${work_dir}/wrapper-own.typ"; then
	report pass "wrapper-own: the document keeps its wrapper and gets the helpers"
else
	report fail "wrapper-own: the document keeps its wrapper and gets the helpers" \
		"one #let my-window( and one #let _cw-page-bg( in wrapper-own.typ"
fi

# The wrapper can also be bound as a closure, which the guard has to see too.
sed 's/^#let my-window(content, ..args) = /#let my-window = (content, ..args) => /' \
	"${work_dir}/wrapper-own.qmd" >"${work_dir}/wrapper-own-closure.qmd"
render wrapper-own-closure typst
if grep -q '^#let my-window = ' "${work_dir}/wrapper-own-closure.typ" &&
	[ "$(grep -cE '^#let my-window( |\()' "${work_dir}/wrapper-own-closure.typ")" -eq 1 ]; then
	report pass "wrapper-own-closure: a closure wrapper replaces the stock one"
else
	report fail "wrapper-own-closure: a closure wrapper replaces the stock one" \
		"one #let my-window, in the closure form, in wrapper-own-closure.typ"
fi

# A document that defines only a helper, whose name starts with the wrapper
# name, still gets the stock wrapper.
sed 's/^#let my-window(content, ..args) = block(stroke: 1pt, content)$/#let my-window-circled-number(n, bg-colour: none) = []/' \
	"${work_dir}/wrapper-own.qmd" >"${work_dir}/wrapper-own-helper.qmd"
render wrapper-own-helper typst
if grep -q '^#let my-window-circled-number(n, bg-colour: none) = \[\]' "${work_dir}/wrapper-own-helper.typ" &&
	[ "$(grep -c '^#let my-window(' "${work_dir}/wrapper-own-helper.typ")" -eq 1 ]; then
	report pass "wrapper-own-helper: a helper definition is not taken for the wrapper"
else
	report fail "wrapper-own-helper: a helper definition is not taken for the wrapper" \
		"the document's helper and one stock #let my-window( in wrapper-own-helper.typ"
fi

# A custom wrapper calls the annotation helper to show code annotations, so
# the helper is written even with both hot-fixes off.
sed 's/^    wrapper: my-window$/    wrapper: my-window\
    hotfix:\
      code-annotations: false\
      skylighting: false/' \
	"${work_dir}/wrapper-own.qmd" >"${work_dir}/wrapper-own-no-hotfix.qmd"
render wrapper-own-no-hotfix typst
if grep -q '^      skylighting: false' "${work_dir}/wrapper-own-no-hotfix.qmd" &&
	grep -q '^#let my-window-annotated-content(' "${work_dir}/wrapper-own-no-hotfix.typ"; then
	report pass "wrapper-own-no-hotfix: the annotation helper is written without the hot-fixes"
else
	report fail "wrapper-own-no-hotfix: the annotation helper is written without the hot-fixes" \
		"hot-fixes off in wrapper-own-no-hotfix.qmd and a #let my-window-annotated-content( in its .typ"
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
forced_auto="$(count_auto_windows "${forced_html}")"
if [ "${forced_labels}" -eq 1 ] && [ "${forced_auto}" -eq 2 ] &&
	grep -q 'data-filename="run.sh"' "${forced_html}"; then
	report pass "auto-label-forced: only the labelled block takes the label in HTML"
else
	report fail "auto-label-forced: only the labelled block takes the label in HTML" \
		"one data-filename=\"Terminal\", two code-window-auto wrappers, and data-filename=\"run.sh\", got ${forced_labels} and ${forced_auto}"
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
	! block_classes "${not_first_html}" | grep -q 'default.*bash'; then
	report pass "language-not-first: a later language class names and highlights the block"
else
	report fail "language-not-first: a later language class names and highlights the block" \
		"two wrappers with data-filename=\"bash\" and no default class before bash, got ${named_bash}"
fi

if block_wrappers "${not_first_html}" | grep -q 'data-filename="default"' &&
	block_wrappers "${not_first_html}" | grep -q 'data-filename="foo"' &&
	[ "$(block_classes "${not_first_html}" | grep -c 'numberSource')" -eq 3 ]; then
	report pass "language-not-first: a numbered block with no language keeps its numbers"
else
	report fail "language-not-first: a numbered block with no language keeps its numbers" \
		"a numberSource class, which Pandoc writes on a numbered block, on the three numbered blocks, data-filename=\"default\" on one and data-filename=\"foo\" on another"
fi

render language-not-first typst
not_first_typ="${work_dir}/language-not-first.typ"
if [ "$(count_typst_windows "${not_first_typ}")" -eq 4 ] &&
	[ "$(grep -c '^#code-window(filename: "bash"' "${not_first_typ}" || true)" -eq 2 ]; then
	report pass "language-not-first: the Typst windows are named after the language"
else
	report fail "language-not-first: the Typst windows are named after the language" \
		"four windows, two of them named bash, in language-not-first.typ"
fi

# ============================================================================
# Quarto's own code blocks are left alone
# ============================================================================

# The front matter of a chapter becomes a quarto-title-block code block.
book_dir="${work_dir}/book"
cp -R "${tests_dir}/fixtures/book" "${book_dir}"
cp -R "${work_dir}/_extensions" "${book_dir}/_extensions"
render book typst
book_typ="${book_dir}/index.typ"
if [ "$(count_typst_windows "${book_typ}")" -eq 1 ] &&
	! grep -q 'quarto-title-block' "${book_typ}"; then
	report pass "book: the chapter title block gets no window"
else
	report fail "book: the chapter title block gets no window" \
		"one window, for the r block, and no quarto-title-block in index.typ"
fi

# ============================================================================
# The derived title bar is in the rendered page
# ============================================================================

# Quarto builds the window of a named block while it reads the document, and
# the filter builds the same window for a derived name. The page then holds the
# title bar before any script runs, so nothing below the block moves on load.
# The block that opts out gets no window, and the marker class is gone.
# $1 rendered file. $2 format name for the report.
check_auto_bar() {
	local auto named
	auto="$(count_auto_windows "$1")"
	named="$(grep -c '<div class="code-with-filename">' "$1" || true)"
	if [ "${auto}" -eq 4 ] && [ "${named}" -eq 1 ]; then
		report pass "auto-bar-render-time ($2): the derived windows are in the page"
	else
		report fail "auto-bar-render-time ($2): the derived windows are in the page" \
			"four code-window-auto wrappers and one plain wrapper, got ${auto} and ${named}"
	fi
	if ! grep -q 'cw-auto' "$1"; then
		report pass "auto-bar-render-time ($2): no marker class is left"
	else
		report fail "auto-bar-render-time ($2): no marker class is left" \
			"no cw-auto in the rendered file"
	fi
	if grep -q 'code-annotation-container-grid' "$1" && grep -q 'Auto listing' "$1"; then
		report pass "auto-bar-render-time ($2): annotations and listing caption are kept"
	else
		report fail "auto-bar-render-time ($2): annotations and listing caption are kept" \
			"a code-annotation-container-grid list and the Auto listing caption"
	fi
}

# Quarto already gives a block with an empty filename a window of its own. The
# filter leaves it alone, so the page holds one window per block and the
# annotation pass, which expects a code block inside each window, renders.
render empty-filename html
empty_windows="$(grep -o '<div class="code-with-filename[" ]' "${work_dir}/empty-filename.html" | wc -l | tr -d ' ')"
if [ "${empty_windows}" -eq 2 ]; then
	report pass "empty-filename: each block gets one window"
else
	report fail "empty-filename: each block gets one window" \
		"two code-with-filename wrappers, got ${empty_windows}"
fi

# Typst gives an empty filename the same meaning: the window draws its title
# bar with no label, and takes no language label in its place.
render empty-filename typst
if grep -q '^#code-window(filename: "", is-auto: false' "${work_dir}/empty-filename.typ"; then
	report pass "empty-filename: Typst draws a window with an empty title"
else
	report fail "empty-filename: Typst draws a window with an empty title" \
		'a #code-window(filename: "", is-auto: false call in empty-filename.typ'
fi

# An executed cell carries its filename in Quarto's registry. An empty one is
# read as a filename there too, so HTML keeps the single window Quarto builds
# and Typst draws a window with an empty title. Needs R and knitr.
if command -v Rscript >/dev/null 2>&1; then
	render empty-filename-cell html
	cell_windows="$({ grep -o '<div class="code-with-filename[" ]' "${work_dir}/empty-filename-cell.html" || true; } | wc -l | tr -d ' ')"
	render empty-filename-cell typst
	if [ "${cell_windows}" -eq 1 ] &&
		[ "$(count_typst_windows "${work_dir}/empty-filename-cell.typ")" -eq 1 ] &&
		grep -q '^#code-window(filename: "", is-auto: false' "${work_dir}/empty-filename-cell.typ"; then
		report pass "empty-filename-cell: a cell with an empty filename gets one window with an empty title"
	else
		report fail "empty-filename-cell: a cell with an empty filename gets one window with an empty title" \
			"one code-with-filename wrapper in HTML, got ${cell_windows}, and one #code-window(filename: \"\", is-auto: false call in Typst"
	fi
else
	report fail "empty-filename-cell: a cell with an empty filename gets one window with an empty title" \
		"Rscript on PATH, with knitr installed"
fi

# ============================================================================
# Annotation markers follow the comment syntax of the block's language
# ============================================================================

# A Markdown block that shows an annotated block as text holds "# <1>", which
# is not a Markdown comment. Quarto leaves it as text, so the Typst output has
# one annotated block. The render compiles the PDF, so a link to a missing
# label stops it.
render literal-annotation-markers typst
annotated_blocks="$(count_in "${work_dir}/literal-annotation-markers.typ" 'annotations: ("')"
literal_markers="$(count_in "${work_dir}/literal-annotation-markers.typ" 'CommentTok("# <1>")')"
if [ "${annotated_blocks}" -eq 1 ] && [ "${literal_markers}" -eq 1 ]; then
	report pass "literal-annotation-markers: markers in a Markdown block stay as text"
else
	report fail "literal-annotation-markers: markers in a Markdown block stay as text" \
		"one annotated block, got ${annotated_blocks}, and the literal marker kept, got ${literal_markers}"
fi

render auto-bar-render-time html
check_auto_bar "${work_dir}/auto-bar-render-time.html" html
render auto-bar-render-time revealjs
check_auto_bar "${work_dir}/auto-bar-render-time.html" revealjs

# ============================================================================

printf '\n%s passed, %s failed\n' "${passed}" "${failed}"
[ "${failed}" -eq 0 ]
