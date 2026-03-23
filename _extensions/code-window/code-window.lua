--- @module code-window
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
local utils = require(quarto.utils.resolve_path('_modules/utils.lua'):gsub('%.lua$', ''))
local code_annotations = nil

-- ============================================================================
-- DEFAULTS AND STATE
-- ============================================================================

--- @class CodeWindowConfig
--- @field enabled boolean Whether code-window styling is enabled
--- @field auto_filename boolean Whether to auto-generate filename from language
--- @field style string Window decoration style ('macos', 'windows', 'default')
--- @field typst_wrapper string Typst wrapper function name
--- @field hotfix_code_annotations boolean Whether to apply the code-annotations hot-fix for Typst
--- @field hotfix_skylighting boolean Whether to apply the Skylighting hot-fix for Typst

local VALID_STYLES = { ['default'] = true, ['macos'] = true, ['windows'] = true }

local DEFAULTS = {
  ['enabled'] = 'true',
  ['auto-filename'] = 'true',
  ['style'] = 'macos',
  ['wrapper'] = 'code-window',
}

local HOTFIX_DEFAULTS = {
  ['code-annotations'] = true,
  ['skylighting'] = true,
}

local CURRENT_FORMAT = nil
local CONFIG = nil
local TYPST_BG_COLOUR = nil
local ANNOTATION_BLOCK_COUNTER = 0

-- ============================================================================
-- LANGUAGE DETECTION
-- ============================================================================

--- Cache of language detection results (lang -> boolean).
local known_language_cache = {}

--- Check if a language is recognised by Pandoc's syntax highlighter.
--- Renders a test CodeBlock to HTML and checks for the sourceCode class.
--- Results are cached to avoid repeated rendering.
--- @param lang string Language identifier
--- @return boolean True if the language is known to Pandoc
local function is_known_language(lang)
  if not lang or lang == '' then
    return false
  end

  if known_language_cache[lang] ~= nil then
    return known_language_cache[lang]
  end

  local test_block = pandoc.CodeBlock('x', pandoc.Attr('', { lang }))
  local html = pandoc.write(pandoc.Pandoc({ test_block }), 'html')
  local is_known = html:find('sourceCode') ~= nil
  known_language_cache[lang] = is_known
  return is_known
end

-- ============================================================================
-- BLOCK-LEVEL STYLE OVERRIDE
-- ============================================================================

--- Read the block-level style override from code-window-style attribute.
--- Returns the validated style value or nil.
--- Strips the attribute from the block.
--- @param block pandoc.CodeBlock Code block element
--- @return string|nil Style override value
local function read_block_style(block)
  local block_style = block.attributes['code-window-style']
  if not block_style or block_style == '' then
    return nil
  end
  block.attributes['code-window-style'] = nil
  if VALID_STYLES[block_style] then
    return block_style
  end
  utils.log_warning(EXTENSION_NAME,
    string.format('Unknown block style "%s", using configured default.', block_style))
  return nil
end

-- ============================================================================
-- TYPST FUNCTION DEFINITION
-- ============================================================================

--- Typst annotation helper functions (state, colour, circled numbers, annotation items).
--- Only injected when at least one hot-fix is active.
local TYPST_ANNOTATION_DEF = [==[
// code-window: annotation state passed to Skylighting via Typst state
#let _cw-annotations = state("cw-annotations", none)

// Derive a contrasting annotation colour from a background fill.
// Light backgrounds get dark circles; dark backgrounds get light circles.
// Uses ITU-R BT.709 luminance coefficients, matching quarto-cli PR #14170.
#let code-window-annote-colour(bg) = {
  if type(bg) == color {
    let comps = bg.components(alpha: false)
    let lum = if comps.len() == 1 {
      comps.at(0) / 100%
    } else {
      0.2126 * comps.at(0) / 100% + 0.7152 * comps.at(1) / 100% + 0.0722 * comps.at(2) / 100%
    }
    if lum < 0.5 { luma(200) } else { luma(60) }
  } else {
    luma(60)
  }
}

#let code-window-circled-number(n, bg-colour: none) = {
  let c = if bg-colour != none { code-window-annote-colour(bg-colour) } else { luma(120) }
  box(baseline: 20%, circle(
    radius: 4.5pt,
    stroke: 0.5pt + c,
  )[#set text(size: 5.5pt, fill: c); #align(center + horizon, str(n))])
}

#let code-window-annotation-item(block-id, n, content) = {
  let lbl-prefix = "cw-" + str(block-id) + "-"
  [#block(above: 0.4em, below: 0.4em)[
    #link(label(lbl-prefix + "line-" + str(n)))[
      #code-window-circled-number(n)
    ]
    #h(0.4em)
    #content
  ] #label(lbl-prefix + "item-" + str(n))]
}

#let code-window-annotated-content(content, annotations: (:), bg-colour: none, block-id: 0) = {
  if annotations.len() > 0 {
    _cw-annotations.update((annotations: annotations, bg-colour: bg-colour, block-id: block-id))
    content
    _cw-annotations.update(none)
  } else {
    content
  }
}
]==]

--- Typst code-window body content template.
--- Uses annotation wrapper when hot-fixes are active, plain content otherwise.
local TYPST_CONTENT_WITH_ANNOTATIONS = [==[
        code-window-annotated-content(
          content,
          annotations: annotations,
          bg-colour: bg-colour,
          block-id: block-id,
        )
]==]

local TYPST_CONTENT_PLAIN = [==[
        content
]==]

--- Build the complete Typst code-window function definition.
--- @param has_hotfixes boolean Whether at least one hot-fix is active
--- @return string Typst function definition(s)
local function build_typst_function_def(has_hotfixes)
  local content_block = has_hotfixes
    and TYPST_CONTENT_WITH_ANNOTATIONS
    or TYPST_CONTENT_PLAIN

  local fn_def = string.format([==[
#let code-window(
  content,
  filename: none,
  is-auto: false,
  style: "macos",
  annotations: (:),
  bg-colour: none,
  block-id: 0,
) = {
  let border-colour = luma(200)
  let surface-fill = luma(237)
  let muted-colour = luma(120)

  let filename-label = if filename != none {
    text(
      size: if is-auto { 0.7em } else { 0.85em },
      weight: 500,
      fill: muted-colour,
      if is-auto { upper(filename) } else { filename },
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

  let title-bar = if style == "macos" {
    grid(
      columns: (auto, 1fr),
      align: (left + horizon, right + horizon),
      gutter: 0.5em,
      stroke: 0pt,
      traffic-lights,
      filename-label,
    )
  } else if style == "windows" {
    grid(
      columns: (1fr, auto),
      align: (left + horizon, right + horizon),
      gutter: 0.5em,
      stroke: 0pt,
      filename-label,
      window-buttons,
    )
  } else {
    // default: plain filename, left-aligned
    filename-label
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
      // Strip code block chrome so content fills flush against the window body.
      // set block() provides defaults for Skylighting blocks (explicit fill preserved).
      // show raw overrides the document-level raw block styling (fill, radius).
      {
        set block(
          width: 100%%,
          inset: 8pt,
          radius: 0pt,
          stroke: none,
          above: 0pt,
          below: 0pt,
        )
        show raw.where(block: true): set block(
          fill: none,
          width: 100%%,
          radius: 0pt,
          stroke: none,
          above: 0pt,
          below: 0pt,
        )
%s      }
    },
  )
}
]==], content_block)

  if has_hotfixes then
    return TYPST_ANNOTATION_DEF .. fn_def
  end
  return fn_def
end

-- ============================================================================
-- TYPST PROCESSING
-- ============================================================================

--- Get the next unique block ID for annotation linking.
--- @return integer
local function next_block_id()
  ANNOTATION_BLOCK_COUNTER = ANNOTATION_BLOCK_COUNTER + 1
  return ANNOTATION_BLOCK_COUNTER
end

--- Build the Typst bg-colour parameter string.
--- @return string Empty string or ', bg-colour: rgb("...")'
local function typst_bg_colour_param()
  if not TYPST_BG_COLOUR then
    return ''
  end
  return string.format(', bg-colour: rgb("%s")', TYPST_BG_COLOUR)
end

--- Build a code-window opening RawBlock for Typst.
--- @param filename string
--- @param is_auto boolean
--- @param style string
--- @param annotations table|nil
--- @param block_id integer
--- @return pandoc.RawBlock
local function typst_code_window_open(filename, is_auto, style, annotations, block_id)
  local annot_param = ''
  if annotations and next(annotations) then
    annot_param = string.format(', annotations: %s, block-id: %d',
      code_annotations.annotations_to_typst_dict(annotations), block_id)
  end

  return pandoc.RawBlock('typst', string.format(
    '#%s(filename: "%s", is-auto: %s, style: "%s"%s%s)[',
    CONFIG.typst_wrapper,
    filename:gsub('"', '\\"'),
    is_auto and 'true' or 'false',
    style,
    annot_param,
    typst_bg_colour_param()
  ))
end

--- Build a standalone annotation wrapper for non-windowed blocks.
--- @param annotations table
--- @param block_id integer
--- @return pandoc.RawBlock opening, pandoc.RawBlock closing
local function typst_annotation_wrapper(annotations, block_id)
  local open = pandoc.RawBlock('typst', string.format(
    '#%s-annotated-content(annotations: %s, block-id: %d%s)[',
    CONFIG.typst_wrapper,
    code_annotations.annotations_to_typst_dict(annotations),
    block_id,
    typst_bg_colour_param()
  ))
  local close = pandoc.RawBlock('typst', ']')
  return open, close
end

-- ============================================================================
-- HTML PROCESSING
-- ============================================================================

--- Process CodeBlock for HTML/Reveal.js formats.
--- Explicit-filename blocks are returned for Quarto to wrap; a marker class
--- is added when a block-level style override is present.
--- Auto-filename blocks are wrapped directly with the style class.
--- @param block pandoc.CodeBlock Code block element
--- @return pandoc.Div|pandoc.CodeBlock Wrapped block or original
local function process_html(block)
  -- Per-block opt-out: code-window-enabled="false" skips window chrome.
  local block_enabled = block.attributes['code-window-enabled']
  if block_enabled then
    block.attributes['code-window-enabled'] = nil
  end
  if block_enabled == 'false' then
    return block
  end

  local block_style = read_block_style(block)
  local explicit_filename = block.attributes['filename']

  if explicit_filename and explicit_filename ~= '' then
    -- Let Quarto create the .code-with-filename wrapper.
    -- Add a marker class for block-level style override; the injected JS
    -- reads it and promotes it to the wrapper div.
    if block_style then
      table.insert(block.classes, 'cw-style-' .. block_style)
    end
    return block
  end

  if not CONFIG.auto_filename then
    return block
  end

  if not block.classes or #block.classes == 0 then
    return block
  end

  local filename = block.classes[1]
  local effective_style = block_style or CONFIG.style

  -- Normalise unknown languages to 'default' so Pandoc renders them
  -- with sourceCode wrapper, copy button, and consistent styling.
  if not is_known_language(filename) then
    block.classes[1] = 'default'
  end

  local filename_header = pandoc.RawBlock(
    'html',
    string.format(
      '<div class="code-with-filename-file"><pre><strong>%s</strong></pre></div>',
      utils.escape_html(filename)
    )
  )

  return pandoc.Div(
    { filename_header, block },
    pandoc.Attr('', { 'code-with-filename', 'code-window-' .. effective_style, 'code-window-auto' })
  )
end

-- ============================================================================
-- FILTER HANDLERS
-- ============================================================================

--- Generate a JS snippet that adds the configured default style class
--- to Quarto-created .code-with-filename wrappers (explicit filenames)
--- and promotes block-level cw-style-* marker classes.
--- @param default_style string The configured default style
--- @return string JavaScript code
local function make_style_js(default_style)
  return string.format([=[
document.addEventListener("DOMContentLoaded",function(){
  document.querySelectorAll(".code-with-filename").forEach(function(el){
    if(/\bcode-window-(macos|windows|default)\b/.test(el.className))return;
    var c=el.querySelector('[class*="cw-style-"]');
    if(c){var m=c.className.match(/cw-style-(\w+)/);if(m){el.classList.add("code-window-"+m[1]);return;}}
    el.classList.add("code-window-%s");
  });
});]=], default_style)
end

--- Load configuration and inject CSS/JS dependencies.
function Meta(meta)
  CURRENT_FORMAT = utils.get_quarto_format()
  local opts = utils.get_options({
    extension = EXTENSION_NAME,
    keys = { 'enabled', 'auto-filename', 'style', 'wrapper' },
    meta = meta,
    defaults = DEFAULTS,
  })

  if not VALID_STYLES[opts['style']] then
    utils.log_warning(EXTENSION_NAME,
      string.format('Unknown style "%s", falling back to "macos".', opts['style']))
  end

  -- Read code-annotations metadata (Quarto standard option).
  local annot_meta = meta['code-annotations']
  local annot_value = annot_meta and pandoc.utils.stringify(annot_meta) or ''
  local annotations_enabled = annot_value ~= 'none' and annot_value ~= 'false'

  -- Read hotfix sub-table from extensions.code-window.hotfix.
  local ext_config = utils.get_extension_config(meta, EXTENSION_NAME)
  local hotfix_meta = ext_config and ext_config['hotfix'] or nil

  -- Deprecation check for old flat skylighting-fix key.
  if ext_config and ext_config['skylighting-fix'] ~= nil then
    utils.log_warning(EXTENSION_NAME,
      '"skylighting-fix" is deprecated. Use "hotfix: { skylighting: true/false }" instead.')
  end

  -- Parse hotfix options with version-based auto-disable.
  local hotfix = {}
  local hotfix_version_override = false
  if hotfix_meta then
    local version_str = hotfix_meta['quarto-version']
    if version_str then
      version_str = pandoc.utils.stringify(version_str)
      if version_str ~= '' then
        local ok, threshold = pcall(pandoc.types.Version, version_str)
        if ok and quarto.version >= threshold then
          hotfix_version_override = true
        end
      end
    end
  end

  for key, default in pairs(HOTFIX_DEFAULTS) do
    if hotfix_version_override then
      hotfix[key] = false
    elseif hotfix_meta and hotfix_meta[key] ~= nil then
      hotfix[key] = pandoc.utils.stringify(hotfix_meta[key]) == 'true'
    else
      hotfix[key] = default
    end
  end

  CONFIG = {
    enabled = opts['enabled'] == 'true',
    auto_filename = opts['auto-filename'] == 'true',
    style = VALID_STYLES[opts['style']] and opts['style'] or 'macos',
    typst_wrapper = opts['wrapper'],
    hotfix_code_annotations = hotfix['code-annotations'],
    hotfix_skylighting = hotfix['skylighting'],
    code_annotations = annotations_enabled,
  }

  -- Cache syntax highlighting background colour for Typst contrast-aware annotations.
  if CURRENT_FORMAT == 'typst' then
    local hm = PANDOC_WRITER_OPTIONS and PANDOC_WRITER_OPTIONS.highlight_method
    if hm then
      local bg = hm['background-color']
      if bg and type(bg) == 'string' then
        TYPST_BG_COLOUR = bg
      end
    end
  end

  if CURRENT_FORMAT == 'html' and CONFIG.enabled then
    utils.ensure_html_dependency({
      name = EXTENSION_NAME,
      version = '0.1.0',
      stylesheets = { 'style.css' },
    })
    utils.ensure_html_dependency({
      name = EXTENSION_NAME .. '-style-init',
      version = '0.1.0',
      head = '<script>' .. make_style_js(CONFIG.style) .. '</script>',
    })
  end

  return meta
end

--- Process CodeBlock elements for HTML/Reveal.js only.
--- Typst processing is handled by the Blocks filter.
function CodeBlock(block)
  if not CURRENT_FORMAT or not CONFIG or not CONFIG.enabled then
    return block
  end

  if CURRENT_FORMAT == 'html' then
    return process_html(block)
  end

  return block
end

-- ============================================================================
-- TYPST BLOCKS FILTER
-- ============================================================================

--- Determine whether a CodeBlock should get code-window chrome.
--- @param block pandoc.CodeBlock
--- @return string|nil filename
--- @return boolean is_auto
--- @return string|nil block_style
--- @return boolean window_opted_out True when code-window-enabled="false" was set
local function resolve_window_params(block)
  -- Per-block opt-out: code-window-enabled="false" skips window chrome.
  local block_enabled = block.attributes['code-window-enabled']
  if block_enabled then
    block.attributes['code-window-enabled'] = nil
  end
  if block_enabled == 'false' then
    return nil, false, nil, true
  end

  local block_style = read_block_style(block)
  local explicit_filename = block.attributes['filename']
  local filename = explicit_filename
  local is_auto = false

  if not filename or filename == '' then
    if CONFIG.auto_filename and block.classes and #block.classes > 0 then
      filename = block.classes[1]
      is_auto = true
    end
  end

  return filename, is_auto, block_style, false
end

--- Process a single CodeBlock for Typst, returning replacement blocks.
--- Handles both code-window wrapping and standalone annotation rendering.
--- @param block pandoc.CodeBlock
--- @param next_block pandoc.Block|nil The block following this CodeBlock
--- @return pandoc.List replacement_blocks Blocks to splice in
--- @return boolean consumed_next Whether the next block was consumed
--- @return integer|nil annotation_block_id Block ID if annotations were found (for parent propagation)
local function process_typst_block(block, next_block)
  local filename, is_auto, block_style, window_opted_out = resolve_window_params(block)
  local has_window = filename and filename ~= ''
  local effective_style = block_style or CONFIG.style

  -- Resolve annotations if enabled and the code-annotations hot-fix is active.
  local annotations = nil
  local should_handle_annotations = CONFIG.code_annotations and CONFIG.hotfix_code_annotations

  if should_handle_annotations then
    local cleaned_text
    cleaned_text, annotations = code_annotations.resolve_annotations(block)
    if annotations then
      block.text = cleaned_text
    end
  end

  -- Strip filename attribute to prevent Quarto's DecoratedCodeBlock (PR #14170).
  if has_window and block.attributes['filename'] then
    block.attributes['filename'] = nil
  end

  local has_annotations = annotations and next(annotations)
  local consumed_next = false
  local result = {}
  local block_id = has_annotations and next_block_id() or 0

  if has_window and has_annotations then
    table.insert(result, typst_code_window_open(
      filename, is_auto, effective_style, annotations, block_id))
    table.insert(result, block)
    table.insert(result, pandoc.RawBlock('typst', ']'))
  elseif has_window then
    table.insert(result, typst_code_window_open(
      filename, is_auto, effective_style, nil, 0))
    table.insert(result, block)
    table.insert(result, pandoc.RawBlock('typst', ']'))
  elseif has_annotations then
    local open, close = typst_annotation_wrapper(annotations, block_id)
    table.insert(result, open)
    table.insert(result, block)
    table.insert(result, close)
  else
    table.insert(result, block)
  end

  -- Consume the following OrderedList if it is an annotation list.
  if has_annotations
      and next_block
      and code_annotations.is_annotation_ordered_list(next_block) then
    local wrapper_prefix = CONFIG.typst_wrapper
    local annot_blocks = code_annotations.ordered_list_to_typst_blocks(
      next_block, wrapper_prefix, block_id)
    for _, ab in ipairs(annot_blocks) do
      table.insert(result, ab)
    end
    consumed_next = true
  end

  local returned_block_id = has_annotations and (not consumed_next) and block_id or nil
  return result, consumed_next, returned_block_id
end

--- Process a flat list of blocks for Typst, handling CodeBlocks and their
--- following OrderedLists. Called recursively on Div contents.
--- @param blocks pandoc.Blocks|pandoc.List
--- @return pandoc.Blocks processed_blocks
--- @return integer|nil pending_annotation_block_id Block ID if the last block had annotations (for parent consumption)
local function process_typst_blocks(blocks)
  local new_blocks = {}
  local pending_annot_block_id = nil
  local i = 1
  while i <= #blocks do
    local blk = blocks[i]

    if blk.t == 'CodeBlock' then
      local next_blk = blocks[i + 1]
      local replacement, consumed_next, annot_id = process_typst_block(blk, next_blk)
      for _, rb in ipairs(replacement) do
        table.insert(new_blocks, rb)
      end
      if consumed_next then
        pending_annot_block_id = nil
        i = i + 2
      else
        pending_annot_block_id = annot_id
        i = i + 1
      end
    elseif blk.t == 'Div' then
      local processed, inner_pending = process_typst_blocks(blk.content)
      blk.content = processed
      table.insert(new_blocks, blk)
      -- If the Div's last processed block had pending annotations,
      -- check if the next sibling is an OrderedList to consume.
      if inner_pending then
        local next_blk = blocks[i + 1]
        if next_blk and code_annotations.is_annotation_ordered_list(next_blk) then
          local annot_blocks = code_annotations.ordered_list_to_typst_blocks(
            next_blk, CONFIG.typst_wrapper, inner_pending)
          for _, ab in ipairs(annot_blocks) do
            table.insert(new_blocks, ab)
          end
          pending_annot_block_id = nil
          i = i + 2
        else
          pending_annot_block_id = inner_pending
          i = i + 1
        end
      else
        pending_annot_block_id = nil
        i = i + 1
      end
    else
      pending_annot_block_id = nil
      table.insert(new_blocks, blk)
      i = i + 1
    end
  end
  return pandoc.Blocks(new_blocks), pending_annot_block_id
end

--- Inject Typst function definition and process code blocks for Typst format.
--- Runs as a Pandoc filter to have full control over the document tree.
function Pandoc(doc)
  if CURRENT_FORMAT ~= 'typst' or not CONFIG or not CONFIG.enabled then
    return doc
  end

  -- Process code blocks and annotations throughout the document tree.
  doc.blocks = process_typst_blocks(doc.blocks)

  -- Guard: check if the function definition is already present.
  local fn_pattern = '#let ' .. CONFIG.typst_wrapper
  for _, blk in ipairs(doc.blocks) do
    if blk.t == 'RawBlock' and blk.format == 'typst'
        and blk.text:find(fn_pattern, 1, true) then
      return doc
    end
  end

  local has_hotfixes = CONFIG.hotfix_code_annotations or CONFIG.hotfix_skylighting
  local fn_def = build_typst_function_def(has_hotfixes)
  if CONFIG.typst_wrapper ~= 'code-window' then
    fn_def = fn_def:gsub('code%-window%-annote%-colour', CONFIG.typst_wrapper .. '-annote-colour')
    fn_def = fn_def:gsub('code%-window%-circled%-number', CONFIG.typst_wrapper .. '-circled-number')
    fn_def = fn_def:gsub('code%-window%-annotation%-item', CONFIG.typst_wrapper .. '-annotation-item')
    fn_def = fn_def:gsub('code%-window%-annotated%-content', CONFIG.typst_wrapper .. '-annotated-content')
    fn_def = fn_def:gsub('#let code%-window%(', '#let ' .. CONFIG.typst_wrapper .. '(')
  end
  table.insert(doc.blocks, 1, pandoc.RawBlock('typst', fn_def))

  return doc
end

-- ============================================================================
-- MODULE EXPORTS
-- ============================================================================

--- Inject the code-annotations module dependency.
--- Called by main.lua before any filter handlers run.
--- @param mod table The code-annotations module
local function set_code_annotations(mod)
  code_annotations = mod
end

return {
  set_code_annotations = set_code_annotations,
  Meta = Meta,
  Pandoc = Pandoc,
  CodeBlock = CodeBlock,
  CONFIG = function() return CONFIG end,
}
