--- @module "code-window"
--- @license MIT
--- @copyright 2026 Mickaël Canouil
--- @author Mickaël Canouil
--- @brief Code block window decorations with multiple styles
--- @description Adds window chrome (macOS traffic lights, Windows title bar
--- buttons, or plain filename) to code blocks in HTML, Reveal.js, and Typst
--- formats. Registered at pre-quarto to process all formats in a single pass.

-- ============================================================================
-- EXTENSION NAME
-- ============================================================================

local EXTENSION_NAME = 'code-window'
local str = require(quarto.utils.resolve_path('_vendor/quarto-lua-modules/string.lua'):gsub('%.lua$', ''))
local log = require(quarto.utils.resolve_path('_vendor/quarto-lua-modules/logging.lua'):gsub('%.lua$', ''))
local meta_mod = require(quarto.utils.resolve_path('_vendor/quarto-lua-modules/metadata.lua'):gsub('%.lua$', ''))
local pdoc = require(quarto.utils.resolve_path('_vendor/quarto-lua-modules/pandoc-helpers.lua'):gsub('%.lua$', ''))
local html_mod = require(quarto.utils.resolve_path('_vendor/quarto-lua-modules/html.lua'):gsub('%.lua$', ''))
local cell_output = require(quarto.utils.resolve_path('_modules/cell-output.lua'):gsub('%.lua$', ''))
local language = require(quarto.utils.resolve_path('_modules/language.lua'):gsub('%.lua$', ''))
local checker = nil

-- ============================================================================
-- DEFAULTS AND STATE
-- ============================================================================

--- @class CodeWindowConfig
--- @field enabled boolean Whether code-window styling is enabled
--- @field auto_filename boolean Whether to auto-generate filename from language
--- @field style string Window decoration style ('macos', 'windows', 'default')
--- @field cell_output boolean Whether the output of an executed cell is framed
--- @field typst_wrapper string Typst wrapper function name

local VALID_STYLES = { ['default'] = true, ['macos'] = true, ['windows'] = true }

--- Prefix of every code block attribute this extension owns, the ones the
--- schema declares and the internal label the language module writes alike.
local ATTRIBUTE_PREFIX = 'code-window-'

--- Defaults for the two cases where the schema cannot answer: a format the
--- extension does not act on, where the check never runs, and a schema that
--- could not be read, which is a state this extension renders through rather
--- than stopping for. Everywhere else _schema.yml decides these seven, so the
--- values below are a fallback and not a second place to change one of them.
--- All seven stay listed, because the second case has nothing else to read
--- from, and an option added to the schema needs an entry here as well or it
--- has no default at all on a format the extension does not act on.
--- Where the two disagree, the schema wins on html and typst, and a format
--- the extension does not act on reads "enabled" alone, which is the one that
--- chooses whether a block's attributes are checked. So keep that one in step
--- with the schema, and treat a difference in the other six as a thing to
--- correct rather than a thing that shows.
local FALLBACK_DEFAULTS = {
  ['enabled'] = 'true',
  ['auto-filename'] = 'true',
  ['style'] = 'macos',
  ['cell-output'] = 'false',
  ['wrapper'] = 'code-window',
  ['collapse'] = 'false',
  ['lines-label'] = 'true',
}

local VALID_COLLAPSE = {
  ['false'] = false,
  ['true'] = 'closed',
  ['closed'] = 'closed',
  ['open'] = 'open',
}

local CURRENT_FORMAT = nil
local CONFIG = nil

-- ============================================================================
-- CELL OUTPUT
-- ============================================================================

--- Check whether the extension acts on the format being rendered. It draws
--- chrome for html, which covers Reveal.js, and for typst, and leaves every
--- other format as Quarto writes it.
--- @return boolean
local function acts_on_format()
  return CURRENT_FORMAT == 'html' or CURRENT_FORMAT == 'typst'
end

--- Check whether this render draws chrome at all: the extension is on, and the
--- format is one it acts on. Every pass that exists only to serve the chrome
--- asks this before it does any work, so none of them has to carry its own
--- copy of the two conditions.
--- @return boolean
local function draws_chrome()
  return CONFIG ~= nil and CONFIG.enabled and acts_on_format()
end

--- Check whether a block holds the output of an executed cell that the engine
--- did not name. Such a block keeps the shape Quarto gave it.
--- @param block pandoc.CodeBlock Code block element
--- @return boolean
local function is_unnamed_cell_output(block)
  return cell_output.is_marked(block) and str.is_empty(block.attributes['filename'])
end

--- Check whether a block holds a chapter's front matter, which Quarto writes
--- in a book rendered to one file and later replaces with the title block.
--- @param block pandoc.CodeBlock Code block element
--- @return boolean
local function is_quarto_block(block)
  return block.classes:includes('quarto-title-block')
end

-- ============================================================================
-- BLOCK-LEVEL STYLE OVERRIDE
-- ============================================================================

--- Turn a schema-resolved boolean back into the "true"/"false" string this
--- file's own comparisons already use. A value the schema rejects arrives
--- here unchanged (the original string the document wrote), and is passed
--- through as-is.
--- @param value any Resolved attribute value
--- @return any
local function stringify_bool(value)
  if type(value) == 'boolean' then
    return value and 'true' or 'false'
  end
  return value
end

--- Take the attributes an author can write off a block the filter processes,
--- and answer the label the language module wrote.
--- Pandoc writes an attribute nothing removes into the HTML as
--- data-code-window-*, so a block this filter ran on carries none of them
--- onward: one call per format path, above every early return, is what keeps
--- that true, and an attribute added to the schema later is covered with no
--- change here.
--- Two prefixed attributes are not author-written and are treated on their
--- own terms. code-window-auto-label is returned rather than dropped, because
--- the windowing paths still need its value. The cell-output marker is left
--- alone, because the Typst pass reads it after this runs, and the
--- cell-output module removes it itself.
--- The HTML path writes code-window-lines-label back afterwards, for the
--- injected script to read and remove in the browser.
--- @param block pandoc.CodeBlock Code block element
--- @return string|nil auto_label Label written by the language module, if any
local function take_block_attributes(block)
  local auto_label = language.auto_label(block)
  local owned = {}
  for key, _ in pairs(block.attributes) do
    if key:sub(1, #ATTRIBUTE_PREFIX) == ATTRIBUTE_PREFIX and not cell_output.is_marker(key) then
      owned[#owned + 1] = key
    end
  end
  for _, key in ipairs(owned) do
    block.attributes[key] = nil
  end
  return auto_label
end

--- Resolve a block's attributes against the schema, then take this
--- extension's attributes off the block.
--- The resolved values are copied into a table of their own before anything
--- is removed. checker:attributes hands back the list it was given when it
--- has no schema to check against, which is a case this extension carries on
--- through by design, and the caller would then hold the block's live
--- attributes. Taking them off would empty the very table every reader below
--- reads, and each per-block override would be ignored with no warning.
--- @param block pandoc.CodeBlock Code block element
--- @return table<string, any> resolved What this block's attributes resolve to
--- @return string|nil auto_label Label written by the language module, if any
local function resolve_and_take(block)
  local resolved = {}
  for key, value in pairs(checker:attributes(block.attributes, 'CodeBlock')) do
    resolved[key] = value
  end
  return resolved, take_block_attributes(block)
end

--- Read the block-level style override from code-window-style attribute.
--- Returns the validated style value or nil.
--- An unrecognised value is not warned about here: the schema check this
--- block's caller already ran (checker:attributes, group "CodeBlock") reports
--- the same mistake in its own words, and this file's own message added
--- nothing beyond restating the fallback, which the schema check's
--- documented policy ("no finding stops a render") already implies for every
--- attribute.
--- @param resolved table<string, any> This block's attributes, resolved against the schema
--- @return string|nil Style override value
local function read_block_style(resolved)
  local block_style = resolved['code-window-style']
  if not block_style or block_style == '' then
    return nil
  end
  if type(block_style) == 'string' and VALID_STYLES[block_style] then
    return block_style
  end
  return nil
end

--- Resolve a collapse value coming from extension options or a code-block
--- attribute. Returns "open"/"closed" when the window should be collapsible,
--- nil when collapsing is off or the value is unrecognised.
--- Both callers are now covered by a schema check that reports an
--- unrecognised value in its own words: the "collapse" document option by
--- checker:options (Meta, below), and the "code-window-collapse" block
--- attribute by checker:attributes on the "CodeBlock" group
--- (read_block_collapse, below). This function used to warn again for both,
--- restating the same enum with no remedy, legal alternative, or
--- format-specific consequence the schema message lacks, so neither call
--- site asks for it any more.
--- raw is never a Lua boolean here, for either caller: the "collapse"
--- document option is read through meta_mod.get_options, which always
--- stringifies, and "code-window-collapse" declares type: string in
--- _schema.yml (not a [boolean, string] union), specifically because a
--- Pandoc attribute value is always a string, so a union type paired with
--- an enum holding an unquoted true/false can never match it: `_coerce`
--- returns a value unchanged as soon as its current Lua type already
--- matches a member of the declared type list, so the string always wins
--- and boolean coercion is never attempted, which made the enum check
--- compare the string "true" against the schema's own boolean `true` and
--- fail on every legal value. No stringify step is needed on this path.
--- @param raw string|nil Raw collapse value
--- @return string|nil Resolved collapse mode ("open"/"closed") or nil
local function resolve_collapse(raw)
  if raw == nil or raw == '' then
    return nil
  end
  local resolved = VALID_COLLAPSE[raw]
  if resolved == nil then
    return nil
  end
  if resolved == false then
    return nil
  end
  return resolved
end

--- Read the per-block collapse override from code-window-collapse attribute.
--- code-window-collapse layers over the "collapse" document option
--- (CONFIG.collapse), which is the reason it must not be read with a bare
--- "or": a resolved boolean false has to reach resolve_collapse and disable
--- collapsing, not fall through to the document option. The schema declares
--- no default for this attribute, so the merged table already answers nil
--- exactly when the document left it unwritten, with no separate presence
--- test needed.
--- @param resolved table<string, any> This block's attributes, resolved against the schema
--- @return string|nil Resolved collapse mode ("open"/"closed") or nil when off
--- @return boolean Whether this block decided, which is what separates an
---   explicit "false" from an attribute the block never wrote
local function read_block_collapse(resolved)
  local raw = resolved['code-window-collapse']
  if raw == nil then
    return nil, false
  end
  local mode = VALID_COLLAPSE[raw]
  if mode == nil then
    -- A value the schema does not accept. The check reports it, and the
    -- document option decides as though the block had written nothing.
    return nil, false
  end
  return mode or nil, true
end

--- Read a highlight-lines spec from the block, looking at the
--- code-window-lines attribute first and falling back to Quarto's
--- code-line-numbers attribute when it carries a non-boolean spec.
--- Returns the cleaned spec string or nil.
--- The "lines-label" option is answered here rather than at each call site,
--- so neither format path repeats the test. code-line-numbers belongs to
--- Quarto and is read, never written.
--- @param block pandoc.CodeBlock Code block element
--- @param resolved table<string, any> This block's attributes, resolved against the schema
--- @return string|nil Line spec to display in the title bar
local function read_block_lines_label(block, resolved)
  if not CONFIG.lines_label then
    return nil
  end

  local raw = resolved['code-window-lines']
  if raw ~= nil and raw ~= '' then
    return raw
  end

  local cln = block.attributes['code-line-numbers']
  if not cln or cln == '' or cln == 'true' or cln == 'false' then
    return nil
  end
  return cln
end

--- @class WindowOverrides
--- @field enabled boolean Whether this block asks for chrome at all
--- @field style string|nil Style this block asks for, in place of the document's
--- @field lines_label string|nil Highlighted-lines spec for the title bar
--- @field no_auto_filename boolean Whether this block refuses a derived name

--- Read what a block asks of the chrome, in the order and the way both format
--- paths ask for it. Collapse is left out, because it is the one override that
--- is HTML only and the Typst path never reads.
--- code-window-enabled declares default: true, and code-window-no-auto-filename
--- declares default: false, each matching this file's own fallback. Neither
--- layers over a document option, so the resolved value answers directly, and
--- the stringified value decides the flag, which is what makes an explicit
--- "false" behave like absence rather than like "true".
--- All four are lookups on the resolved table and on the block, and take
--- nothing off the block, which take_block_attributes already did. So a caller
--- may read them all before it tests the opt-out, and their order is free.
--- @param block pandoc.CodeBlock Code block element
--- @param resolved table<string, any> This block's attributes, resolved against the schema
--- @return WindowOverrides
local function read_window_overrides(block, resolved)
  return {
    enabled = stringify_bool(resolved['code-window-enabled']) ~= 'false',
    style = read_block_style(resolved),
    lines_label = read_block_lines_label(block, resolved),
    no_auto_filename = stringify_bool(resolved['code-window-no-auto-filename']) == 'true',
  }
end

-- ============================================================================
-- TYPST FUNCTION DEFINITION
-- ============================================================================

--- Typst colour helpers for adaptive theme support.
--- Always injected so the code-window function can derive border, surface,
--- muted, and label colours from the page background at render time.
local TYPST_COLOUR_HELPERS = [==[
// code-window: adaptive colour helpers (derive UI tones from page background)
#let _cw-page-bg() = {
  let f = page.fill
  if type(f) == color { f } else { luma(255) }
}

#let _cw-fg(bg) = {
  let comps = bg.components(alpha: false)
  let lum = if comps.len() == 1 {
    comps.at(0) / 100%
  } else {
    0.2126 * comps.at(0) / 100% + 0.7152 * comps.at(1) / 100% + 0.0722 * comps.at(2) / 100%
  }
  if lum < 0.5 { luma(255) } else { luma(0) }
}
]==]

--- Typst window state and the replacement for Quarto's filename helper.
--- Quarto draws a block with a filename through quarto-code-filename. The
--- filter keeps Quarto's own helper under another name, then replaces it with
--- one that reads the window state the filter sets before each block. A block
--- that refuses the window, or one the filter never visited, goes to Quarto's
--- helper. Each call clears the state it read, so a block the filter never
--- visited does not take the state of the block before it. "code-window" is
--- renamed with the wrapper option.
local TYPST_FILENAME_HELPER = [==[
#let _cw-window = state("cw-window", none)

#let _cw-native-filename = quarto-code-filename

#let quarto-code-filename(filename, body) = context {
  let s = _cw-window.get()
  _cw-window.update(none)
  if s == none or not s.enabled {
    _cw-native-filename(filename, body)
  } else {
    code-window(
      body,
      filename: filename,
      is-auto: s.is-auto,
      style: s.style,
      lines-label: s.lines-label,
    )
  }
}
]==]

--- Build the complete Typst code-window function definition: the colour
--- helpers, the window function, and the replacement for Quarto's filename
--- helper, in that order.
--- @param with_window boolean Whether to define the window function, which a
--- document that defines its own does not need
--- @return string Typst function definition(s)
local function build_typst_function_def(with_window)
  local fn_def = string.format([==[
#let code-window(
  content,
  filename: none,
  is-auto: false,
  style: "macos",
  lines-label: none,
) = {
  context {
  let page-bg = _cw-page-bg()
  let fg = _cw-fg(page-bg)
  let border-colour = color.mix((fg, 15%%), (page-bg, 85%%))
  let surface-fill = color.mix((fg, 5%%), (page-bg, 95%%))
  let muted-colour = color.mix((fg, 50%%), (page-bg, 50%%))
  let label-colour = color.mix((fg, 65%%), (page-bg, 35%%))
  let outer-code-style = quarto-code-block-style.get()

  let filename-label = if filename != none {
    text(
      size: if is-auto { 0.7em } else { 0.85em },
      weight: 500,
      fill: label-colour,
      if is-auto { upper(filename) } else { filename },
    )
  }

  let lines-chip = if lines-label != none {
    box(
      inset: (x: 0.4em, y: 0.05em),
      outset: (y: 0.15em),
      radius: 3pt,
      fill: color.mix((fg, 10%%), (page-bg, 90%%)),
      stroke: 0.5pt + border-colour,
      text(size: 0.7em, weight: 500, fill: label-colour, lines-label),
    )
  }

  let traffic-lights = box(
    inset: (right: 0.5em),
    stack(
      dir: ltr,
      spacing: 0.425em,
      circle(radius: 0.425em, fill: rgb("#ff5f56"), stroke: none),
      circle(radius: 0.425em, fill: rgb("#ffbd2e"), stroke: none),
      circle(radius: 0.425em, fill: rgb("#27c93f"), stroke: none),
    ),
  )

  let window-buttons = box(
    inset: (left: 0.5em),
    {
      set line(stroke: 1pt + muted-colour)
      stack(
        dir: ltr,
        spacing: 0.8em,
        // Minimise (horizontal line)
        box(width: 0.6em, height: 0.6em, align(horizon, line(length: 100%%))),
        // Maximise (square)
        box(width: 0.6em, height: 0.6em, stroke: 1pt + muted-colour),
        // Close (x)
        box(width: 0.6em, height: 0.6em, {
          place(line(start: (0%%, 0%%), end: (100%%, 100%%)))
          place(line(start: (100%%, 0%%), end: (0%%, 100%%)))
        }),
      )
    },
  )

  let _label-with-chip = if lines-chip != none {
    stack(dir: ltr, spacing: 0.5em, filename-label, lines-chip)
  } else {
    filename-label
  }

  let title-bar = if style == "macos" {
    grid(
      columns: (auto, 1fr),
      align: (left + horizon, right + horizon),
      gutter: 0.5em,
      stroke: 0pt,
      traffic-lights,
      _label-with-chip,
    )
  } else if style == "windows" {
    grid(
      columns: (1fr, auto),
      align: (left + horizon, right + horizon),
      gutter: 0.5em,
      stroke: 0pt,
      _label-with-chip,
      window-buttons,
    )
  } else {
    // default: plain filename, left-aligned
    _label-with-chip
  }

  block(
    width: 100%%,
    stroke: 1pt + border-colour,
    radius: 8pt,
    clip: true,
    {
      block(
        width: 100%%,
        fill: surface-fill,
        inset: (x: 1em, y: 0.6em),
        below: 0pt,
        radius: 0pt,
        stroke: (bottom: 1pt + border-colour),
        sticky: true,
        title-bar,
      )
      // The window draws the border, so Quarto's code blocks inside it lose
      // their own radius and outline, and get them back after the window.
      // set block() only removes the spacing around the code block: a wider
      // rule would also reach the blocks inside Quarto's annotation circles.
      // show raw removes the fill of native code blocks.
      {
        set block(above: 0pt, below: 0pt)
        show raw.where(block: true): set block(fill: none)
        quarto-code-block-style.update((..outer-code-style, radius: 0pt, stroke: none))
        content
        quarto-code-block-style.update(outer-code-style)
      }
    },
  )
  }
}
]==])

  if not with_window then
    fn_def = ''
  end
  return TYPST_COLOUR_HELPERS .. fn_def .. TYPST_FILENAME_HELPER
end

-- ============================================================================
-- TYPST PROCESSING
-- ============================================================================

--- Escape a string for embedding in a Typst double-quoted string literal.
--- @param s string
--- @return string
local function typst_escape_string(s)
  return (s:gsub('\\', '\\\\'):gsub('"', '\\"'))
end

--- @class WindowState
--- @field enabled boolean Whether the block gets the window
--- @field is_auto boolean Whether the name was derived rather than written
--- @field style string Window decoration style
--- @field lines_label string|nil Highlighted-lines spec for the title bar

--- Build the raw Typst block that sets the window state for the block after
--- it. Every block the filter visits sets every field, so a block never
--- inherits a value from the block before it.
--- @param params WindowState
--- @return pandoc.RawBlock
local function typst_window_state(params)
  local lines_label = 'none'
  if params.lines_label and params.lines_label ~= '' then
    lines_label = '"' .. typst_escape_string(params.lines_label) .. '"'
  end
  return pandoc.RawBlock('typst', string.format(
    '#_cw-window.update((enabled: %s, is-auto: %s, style: "%s", lines-label: %s))',
    tostring(params.enabled),
    tostring(params.is_auto),
    params.style,
    lines_label
  ))
end

-- ============================================================================
-- HTML PROCESSING
-- ============================================================================

--- Process CodeBlock for HTML/Reveal.js formats.
--- Explicit-filename blocks are returned for Quarto to wrap; a marker class
--- is added when a block-level style override is present.
--- Auto-filename blocks are wrapped directly with the style class.
--- The block reaches here with its code-window attributes already taken off
--- by take_block_attributes, so every value below is read from the resolved
--- table and the block carries none of them onward.
--- @param block pandoc.CodeBlock Code block element
--- @param resolved table<string, any> This block's attributes, resolved against the schema
--- @param auto_label string|nil Label written by the language module, if any
--- @return pandoc.Div|pandoc.CodeBlock Wrapped block or original
local function process_html(block, resolved, auto_label)
  local overrides = read_window_overrides(block, resolved)

  -- Per-block opt-out: code-window-enabled="false" skips window chrome.
  if not overrides.enabled then
    return block
  end

  local block_collapse, block_decided = read_block_collapse(resolved)
  local effective_collapse = block_collapse
  if not block_decided then
    effective_collapse = CONFIG.collapse
  end
  local explicit_filename = block.attributes['filename']

  -- Add the marker classes and the chip the injected script reads. Both
  -- branches below end this way, on the same block this closure captures.
  local function mark()
    if overrides.style then
      table.insert(block.classes, 'cw-style-' .. overrides.style)
    end
    -- A block that turned collapsing off is marked as well. The script reads
    -- the absence of a marker as "this block said nothing" and falls back to
    -- the document setting, so an opt-out needs a marker of its own.
    if effective_collapse then
      table.insert(block.classes, 'cw-collapse-' .. effective_collapse)
    elseif block_decided and CONFIG.collapse then
      table.insert(block.classes, 'cw-collapse-none')
    end
    if overrides.lines_label then
      block.attributes['code-window-lines-label'] = overrides.lines_label
    end
  end

  if explicit_filename and explicit_filename ~= '' then
    -- Let Quarto create the .code-with-filename wrapper, and mark the block so
    -- the injected script can promote a block-level override onto that wrapper.
    mark()
    return block
  end

  if overrides.no_auto_filename or not (auto_label or CONFIG.auto_filename) then
    return block
  end

  -- Blocks with a language of their own are labelled with its class.
  -- Set the filename attribute so Quarto creates its own .code-with-filename
  -- wrapper. This preserves the CodeBlock+OrderedList sibling structure
  -- needed by Quarto's code-annotations processor.
  block.attributes['filename'] = auto_label or block.classes[1]
  table.insert(block.classes, 'cw-auto')
  mark()

  return block
end

-- ============================================================================
-- FILTER HANDLERS
-- ============================================================================

--- Generate a JS snippet that builds .code-with-filename wrappers for
--- auto-filename blocks (marked with cw-auto at pre-quarto), applies the
--- configured default style class to all .code-with-filename wrappers,
--- promotes block-level cw-style-* / cw-collapse-* marker classes, inserts
--- a highlighted-lines chip when data-code-window-lines-label is set on the inner
--- pre, and wraps collapsible windows in a <details> element where the
--- title bar acts as the <summary>.
--- @param default_style string The configured default style
--- @param default_collapse string|nil Default collapse mode ("open"/"closed"/nil)
--- @return string JavaScript code
local function make_style_js(default_style, default_collapse)
  local default_collapse_js = default_collapse and ('"' .. default_collapse .. '"') or 'null'
  return string.format([=[
document.addEventListener("DOMContentLoaded",function(){
  var DEFAULT_COLLAPSE=%s;
  document.querySelectorAll("pre.cw-auto").forEach(function(pre){
    var fn=pre.closest("[data-filename]");
    if(!fn)return;
    var name=fn.getAttribute("data-filename");
    if(!name)return;
    var scaffold=pre.closest(".code-copy-outer-scaffold")||pre.closest(".sourceCode");
    if(!scaffold)return;
    var w=document.createElement("div");
    w.className="code-with-filename code-window-auto";
    var tb=document.createElement("div");
    tb.className="code-with-filename-file";
    var tp=document.createElement("pre");
    var ts=document.createElement("strong");
    ts.textContent=name;
    tp.appendChild(ts);tb.appendChild(tp);
    scaffold.parentNode.insertBefore(w,scaffold);
    w.appendChild(tb);w.appendChild(scaffold);
    pre.classList.remove("cw-auto");
  });
  function findMarkerSource(el){
    return el.querySelector('pre[class*="cw-style-"],pre[class*="cw-collapse-"],pre[data-code-window-lines-label]')
      ||el.querySelector('[class*="cw-style-"],[class*="cw-collapse-"],[data-code-window-lines-label]');
  }
  document.querySelectorAll(".code-with-filename").forEach(function(el){
    var marker=findMarkerSource(el);
    var styleApplied=/\bcode-window-(macos|windows|default)\b/.test(el.className);
    if(!styleApplied){
      var sm=marker&&marker.className.match(/cw-style-(\w+)/);
      if(sm){el.classList.add("code-window-"+sm[1]);marker.classList.remove(sm[0]);}
      else{el.classList.add("code-window-%s");}
    }
    var collapse=null;
    if(marker){
      var cm=marker.className.match(/cw-collapse-(open|closed|none)/);
      if(cm){collapse=cm[1]==='none'?false:cm[1];marker.classList.remove(cm[0]);}
    }
    if(collapse===null&&DEFAULT_COLLAPSE){collapse=DEFAULT_COLLAPSE;}
    if(marker&&marker.hasAttribute("data-code-window-lines-label")){
      var spec=marker.getAttribute("data-code-window-lines-label");
      marker.removeAttribute("data-code-window-lines-label");
      var titleBar=el.querySelector(".code-with-filename-file");
      if(titleBar&&!titleBar.querySelector(".code-with-filename-lines")){
        var chip=document.createElement("span");
        chip.className="code-with-filename-lines";
        chip.textContent="L"+spec.replace(/,/g,",\u200B");
        titleBar.appendChild(chip);
      }
    }
    if(collapse&&!el.classList.contains("code-window-collapsible")){
      var titleBar=el.querySelector(".code-with-filename-file");
      if(titleBar){
        var details=document.createElement("details");
        details.className=el.className+" code-window-collapsible";
        if(collapse==="open"){details.open=true;}
        var summaryEl=document.createElement("summary");
        summaryEl.className="code-with-filename-file";
        while(titleBar.firstChild){summaryEl.appendChild(titleBar.firstChild);}
        titleBar.parentNode.removeChild(titleBar);
        details.appendChild(summaryEl);
        while(el.firstChild){details.appendChild(el.firstChild);}
        el.parentNode.replaceChild(details,el);
      }
    }
  });
});]=], default_collapse_js, default_style)
end

--- Load configuration and inject CSS/JS dependencies.
function Meta(meta)
  CURRENT_FORMAT = pdoc.get_quarto_format()

  -- This is the pass that reads the configuration, so the check runs here,
  -- before the first option is read. An option the check rejects is still
  -- read below, because the report says what the extension cannot use and the
  -- document renders either way. Only a format the extension acts on reports,
  -- because nothing it could say applies anywhere else.
  -- The check also answers what the schema declares each option defaults to,
  -- so those values are kept rather than dropped and rebuilt by hand here.
  -- They arrive typed, and every comparison below reads a string, so each one
  -- goes through stringify_bool on the way into the table.
  local schema_defaults = {}
  if acts_on_format() then
    schema_defaults = checker:options(meta)
  end

  -- The schema is read first and the fallback fills only what it leaves
  -- unanswered, so on html and typst an option added to _schema.yml and to the
  -- key list below needs nothing more. Anywhere else the check above never
  -- runs, so the same option also needs an entry in FALLBACK_DEFAULTS or it
  -- has no default there. Reading the fallback first would have made it the
  -- list of options allowed to have a default at all, on every format, which
  -- is the coupling this change exists to remove. What arrives is one entry
  -- per option that declares a default of its own, and get_options reads only
  -- the keys named below.
  local defaults = {}
  for key, declared in pairs(schema_defaults) do
    defaults[key] = stringify_bool(declared)
  end
  for key, fallback in pairs(FALLBACK_DEFAULTS) do
    if defaults[key] == nil then
      defaults[key] = fallback
    end
  end

  local opts = meta_mod.get_options({
    extension = EXTENSION_NAME,
    keys = {
      'enabled', 'auto-filename', 'style', 'cell-output', 'wrapper', 'collapse', 'lines-label',
    },
    meta = meta,
    defaults = defaults,
  })

  -- checker:options (above) already reports an unrecognised "style" value in
  -- its own words; this used to warn again with no remedy, legal
  -- alternative, or format-specific consequence the schema message lacks
  -- (the same shape already removed for "collapse"), so it is silent here.
  -- The fallback (VALID_STYLES[opts['style']] and opts['style'] or 'macos',
  -- below in CONFIG) is unchanged.

  local global_collapse = resolve_collapse(opts['collapse'])

  CONFIG = {
    enabled = opts['enabled'] == 'true',
    auto_filename = opts['auto-filename'] == 'true',
    style = VALID_STYLES[opts['style']] and opts['style'] or 'macos',
    cell_output = opts['cell-output'] == 'true',
    typst_wrapper = opts['wrapper'],
    collapse = global_collapse,
    lines_label = opts['lines-label'] == 'true',
  }

  if CURRENT_FORMAT == 'html' and CONFIG.enabled then
    html_mod.ensure_html_dependency({
      name = EXTENSION_NAME,
      stylesheets = { 'style.css' },
    })
    html_mod.ensure_html_dependency({
      name = EXTENSION_NAME .. '-style-init',
      head = '<script>' .. make_style_js(CONFIG.style, CONFIG.collapse) .. '</script>',
    })
  end

  return meta
end

--- Process CodeBlock elements for HTML/Reveal.js only.
--- Typst processing is handled by the Blocks filter.
--- This handler runs on every CodeBlock structurally, for every format,
--- because a plain `CodeBlock` filter entry is not format-scoped the way
--- CONFIG.enabled or CURRENT_FORMAT are. For a Typst render, the same block
--- is already checked once by process_typst_block through the Pandoc filter
--- above it in main.lua's filter list, so checker:attributes is called here
--- only in the two branches that do not overlap with that pass: the
--- disabled/unconfigured branch (where the Typst pass never runs at all,
--- because Pandoc() returns before reaching it) and the html branch (where
--- the Typst pass never runs either, because it is typst-only). Calling it
--- unconditionally at the top of this function double-validated every
--- CodeBlock-group attribute the Typst path leaves unstripped, such as
--- code-window-collapse, which is HTML-only and never read on that path.
--- Within the html branch, the check runs before the is_plain_output return,
--- not after: process_typst_block (below) checks every attribute
--- unconditionally, before its own is_unnamed_cell_output test, so an
--- output-of-an-executed-cell block is validated on the Typst path even
--- though nothing about it is otherwise touched. The html branch matches
--- that rather than skipping validation for the same kind of block, so the
--- same document reports the same finding in both formats.
function CodeBlock(block)
  if is_quarto_block(block) then
    return nil
  end

  -- The Typst path reads the marker in the Pandoc filter, which runs first, so
  -- this pass is where it is removed for every format.
  local is_plain_output = is_unnamed_cell_output(block)
  if cell_output.is_marked(block) then
    cell_output.strip(block)
  end

  -- A filter that draws nothing changes nothing an author wrote. The
  -- attributes it would read stay on the block and reach the output, which is
  -- also what a document with this extension not installed produces. Only
  -- code-window-auto-label goes. The language module no longer writes it in
  -- either of the two branches that clear it, since it asks the same question
  -- before it runs, so what is left to clear is a document that wrote the
  -- extension's own attribute name on a fence by hand. This holds for a filter
  -- switched off, below, and for a format the extension does not act on, at
  -- the end of this function.
  if not CURRENT_FORMAT or not CONFIG or not CONFIG.enabled then
    checker:attributes(block.attributes, 'CodeBlock')
    block.attributes['code-window-auto-label'] = nil
    return block
  end

  if CURRENT_FORMAT == 'html' then
    local resolved, auto_label = resolve_and_take(block)
    if is_plain_output then
      return block
    end
    return process_html(block, resolved, auto_label)
  end

  -- Typst is finished by the Pandoc filter ahead of this one, which takes the
  -- attributes off there. Every other format draws no chrome, so the block
  -- keeps what its author wrote and loses only the label, which a writer that
  -- preserves attributes would otherwise print. Nothing writes that label here
  -- any more, for the reason given above, so this guards a hand-written one.
  block.attributes['code-window-auto-label'] = nil
  return block
end

-- ============================================================================
-- TYPST BLOCKS FILTER
-- ============================================================================

--- Determine whether a CodeBlock should get code-window chrome.
--- The block reaches here with its code-window attributes already taken off
--- by take_block_attributes, as on the HTML path.
--- @param block pandoc.CodeBlock
--- @param resolved table<string, any> This block's attributes, resolved against the schema
--- @param auto_label string|nil Label written by the language module, if any
--- @return string|nil filename
--- @return boolean is_auto
--- @return string|nil block_style
--- @return string|nil lines_label Highlighted-lines spec for the title bar
local function resolve_window_params(block, resolved, auto_label)
  local overrides = read_window_overrides(block, resolved)

  -- Per-block opt-out: code-window-enabled="false" skips window chrome.
  if not overrides.enabled then
    return nil, false, nil, nil
  end

  local filename = block.attributes['filename']
  local is_auto = false

  if (not filename or filename == '') and not overrides.no_auto_filename then
    -- A label asks for a window whatever auto-filename says.
    if auto_label then
      filename = auto_label
      is_auto = true
    elseif CONFIG.auto_filename and block.classes and #block.classes > 0 then
      filename = block.classes[1]
      is_auto = true
    end
  end

  return filename, is_auto, overrides.style, overrides.lines_label
end

--- Check if a Div is Quarto's DecoratedCodeBlock wrapper.
--- @param div pandoc.Div
--- @return boolean
local function is_decorated_codeblock(div)
  return div.attributes['__quarto_custom_type'] == 'DecoratedCodeBlock'
end

--- Extract the CodeBlock from a DecoratedCodeBlock Div.
--- Structure: DecoratedCodeBlock Div > scaffold Div > CodeBlock
--- @param div pandoc.Div
--- @return pandoc.CodeBlock|nil
local function extract_codeblock(div)
  for _, child in ipairs(div.content) do
    if child.t == 'CodeBlock' then
      return child
    elseif child.t == 'Div' then
      local found = extract_codeblock(child)
      if found then return found end
    end
  end
  return nil
end

--- Read the filename from Quarto's internal custom node registry for a
--- DecoratedCodeBlock Div. Quarto stores the #| filename: value there rather
--- than as a plain Pandoc attribute on the inner CodeBlock.
--- @param div pandoc.Div A DecoratedCodeBlock Div
--- @return string|nil filename, or nil when the data is unavailable
local function get_decorated_codeblock_filename(div)
  local custom_id = div.attributes['__quarto_custom_id']
  if not custom_id then return nil end
  if not (_quarto and _quarto.ast and _quarto.ast.custom_node_data) then return nil end
  local entry = _quarto.ast.custom_node_data[custom_id]
  if type(entry) == 'table' and entry.filename and entry.filename ~= '' then
    return entry.filename
  end
  return nil
end

--- Build the window state for a block that Quarto already wrapped in its
--- filename node, from the attributes of the code block inside it.
--- @param div pandoc.Div A DecoratedCodeBlock Div
--- @return pandoc.RawBlock|nil State block, or nil when the node holds no code block for the filter
local function decorated_window_state(div)
  local block = extract_codeblock(div)
  if not block or is_quarto_block(block) then
    return nil
  end
  local resolved = resolve_and_take(block)
  local overrides = read_window_overrides(block, resolved)
  return typst_window_state({
    enabled = overrides.enabled,
    is_auto = false,
    style = overrides.style or CONFIG.style,
    lines_label = overrides.lines_label,
  })
end

--- Frame a code block that has no filename of its own. A block with a derived
--- name is put in Quarto's filename node, which Quarto built for the blocks
--- with a filename before this filter ran, and the window state goes before it.
--- Every other block is returned as it is, its own attributes taken off.
--- @param block pandoc.CodeBlock
--- @return pandoc.Block[] Blocks to put in place of the code block
local function frame_typst_codeblock(block)
  if is_quarto_block(block) then
    return { block }
  end
  -- Check this block's own attributes against the CodeBlock group of the
  -- schema before anything below reads them.
  local resolved, auto_label = resolve_and_take(block)
  if is_unnamed_cell_output(block) then
    return { block }
  end
  local filename, is_auto, block_style, lines_label =
    resolve_window_params(block, resolved, auto_label)
  if not is_auto or str.is_empty(filename) then
    return { block }
  end
  return {
    typst_window_state({
      enabled = true,
      is_auto = true,
      style = block_style or CONFIG.style,
      lines_label = lines_label,
    }),
    -- The constructor returns more than the node, and a call at the end of a
    -- table takes every value it returns. The parentheses keep the node only.
    (quarto.DecoratedCodeBlock({ filename = filename, code_block = block })),
  }
end

--- Walk a list of blocks for Typst and set the window state before each block
--- that Quarto draws through its filename helper. The state block goes before
--- Quarto's node, at the same level, and nothing goes between a block and the
--- block after it, so Quarto still pairs a code block with its annotation list.
--- Inside a layout, the state and the node share one Div, so the layout keeps
--- one cell for them.
--- @param blocks pandoc.Blocks|pandoc.List
--- @param in_layout boolean|nil Whether the blocks are the cells of a layout
--- @return pandoc.Blocks
local function frame_typst_blocks(blocks, in_layout)
  local result = pandoc.Blocks({})
  local i = 1
  -- Insert the framed blocks of one code block. In a layout, they share one
  -- Div with the annotation list after them, so the layout keeps one cell for
  -- them and Quarto still pairs the block with its list.
  local function insert_framed(framed)
    if in_layout and #framed > 1 then
      local next_blk = blocks[i + 1]
      if next_blk and next_blk.t == 'OrderedList' then
        table.insert(framed, next_blk)
        i = i + 1
      end
      result:insert(pandoc.Div(framed))
    else
      result:extend(framed)
    end
  end
  while i <= #blocks do
    local blk = blocks[i]
    if blk.t == 'CodeBlock' then
      insert_framed(frame_typst_codeblock(blk))
    elseif blk.t == 'Div' and is_decorated_codeblock(blk) then
      local state = decorated_window_state(blk)
      insert_framed(state and { state, blk } or { blk })
    elseif blk.t == 'Div' then
      -- The layout of an executed cell places its outputs. Its code is the
      -- first block of the cell, and its window state goes before the cell.
      local is_layout = not blk.classes:includes('cell') and (
        blk.attributes['layout-ncol']
        or blk.attributes['layout-nrow']
        or blk.attributes['layout'])
      blk.content = frame_typst_blocks(blk.content, is_layout)
      -- Quarto reads the code of an executed cell as the first block of the
      -- cell, so the window state of that code goes before the cell instead.
      local first = blk.content[1]
      if blk.classes:includes('cell') and first
          and first.t == 'RawBlock' and first.text:find('#_cw-window.update', 1, true) then
        result:insert(first)
        blk.content:remove(1)
      end
      result:insert(blk)
    elseif blk.t == 'BlockQuote' then
      blk.content = frame_typst_blocks(blk.content)
      result:insert(blk)
    elseif blk.t == 'BulletList' or blk.t == 'OrderedList' then
      for j, item in ipairs(blk.content) do
        blk.content[j] = frame_typst_blocks(item)
      end
      result:insert(blk)
    elseif blk.t == 'DefinitionList' then
      for _, def_item in ipairs(blk.content) do
        for k, body in ipairs(def_item[2]) do
          def_item[2][k] = frame_typst_blocks(body)
        end
      end
      result:insert(blk)
    else
      result:insert(blk)
    end
    i = i + 1
  end
  return result
end

--- Walk HTML document blocks and transfer the filename from any DecoratedCodeBlock
--- outer Div to its inner CodeBlock, so process_html sees an explicit filename
--- and does not trigger auto-filename (which would otherwise produce a second
--- .code-with-filename wrapper alongside Quarto's own).
--- @param blocks pandoc.Blocks
--- @return pandoc.Blocks
local function fix_html_decorated_filenames(blocks)
  return blocks:walk({
    Div = function(div)
      if not is_decorated_codeblock(div) then return nil end
      local fn = get_decorated_codeblock_filename(div)
      if not fn then return nil end
      local inner_block = extract_codeblock(div)
      if inner_block and str.is_empty(inner_block.attributes['filename']) then
        inner_block.attributes['filename'] = fn
      end
      return div
    end
  })
end

--- Inject Typst function definition and process code blocks for Typst format.
--- Also repairs HTML DecoratedCodeBlock filename propagation.
--- Runs as a Pandoc filter to have full control over the document tree.
function Pandoc(doc)
  if not CONFIG or not CONFIG.enabled then
    return doc
  end

  -- For HTML: transfer filenames from DecoratedCodeBlock Divs to inner
  -- CodeBlocks before the CodeBlock filter runs, preventing auto-filename
  -- from adding a second .code-with-filename wrapper.
  if CURRENT_FORMAT == 'html' then
    doc.blocks = fix_html_decorated_filenames(doc.blocks)
    return doc
  end

  if CURRENT_FORMAT ~= 'typst' then
    return doc
  end

  -- Set the window state before every block Quarto draws with a filename.
  doc.blocks = frame_typst_blocks(doc.blocks)

  -- A document that defines the window function keeps its own. The state and
  -- the filename helper are still needed, as every framed block uses them,
  -- and they go after that definition, because Typst only sees the names
  -- defined before.
  local fn_pattern = '#let ' .. CONFIG.typst_wrapper .. '('
  local insert_at = 1
  for idx, blk in ipairs(doc.blocks) do
    if blk.t == 'RawBlock' and blk.format == 'typst'
        and blk.text:find(fn_pattern, 1, true) then
      insert_at = idx + 1
      break
    end
  end

  local fn_def = build_typst_function_def(insert_at == 1)
  if CONFIG.typst_wrapper ~= 'code-window' then
    fn_def = fn_def:gsub('code%-window%(', CONFIG.typst_wrapper .. '(')
  end
  table.insert(doc.blocks, insert_at, pandoc.RawBlock('typst', fn_def))

  return doc
end

-- ============================================================================
-- MODULE EXPORTS
-- ============================================================================

--- Inject the schema checker.
--- Called by main.lua before any filter handlers run.
--- @param mod table The checker built from the vendored validator
local function set_checker(mod)
  checker = mod
end

return {
  set_checker = set_checker,
  Meta = Meta,
  Pandoc = Pandoc,
  CodeBlock = CodeBlock,
  CONFIG = function() return CONFIG end,
  draws_chrome = draws_chrome,
  is_quarto_block = is_quarto_block,
}
