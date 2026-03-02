--- @module code-window
--- @license MIT
--- @copyright 2026 Mickaël Canouil
--- @author Mickaël Canouil
--- @version 0.1.0
--- @brief Code block window decorations with multiple styles
--- @description Adds window chrome (macOS traffic lights, Windows title bar
--- buttons, or plain filename) to code blocks in HTML, Reveal.js, and Typst
--- formats. Registered at pre-quarto to process all formats in a single pass.

-- ============================================================================
-- EXTENSION NAME
-- ============================================================================

local EXTENSION_NAME = 'code-window'
local utils = require(quarto.utils.resolve_path('_modules/utils.lua'):gsub('%.lua$', ''))

-- ============================================================================
-- DEFAULTS AND STATE
-- ============================================================================

--- @class CodeWindowConfig
--- @field enabled boolean Whether code-window styling is enabled
--- @field auto_filename boolean Whether to auto-generate filename from language
--- @field style string Window decoration style ('macos', 'windows', 'default')
--- @field typst_wrapper string Typst wrapper function name

local VALID_STYLES = { ['default'] = true, ['macos'] = true, ['windows'] = true }

local DEFAULTS = {
  ['enabled'] = 'true',
  ['auto-filename'] = 'true',
  ['style'] = 'macos',
  ['wrapper'] = 'code-window',
}

local CURRENT_FORMAT = nil
local CONFIG = nil

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

--- Typst function definition for code-window rendering.
--- Injected once at the start of the document body.
local TYPST_FUNCTION_DEF = [==[
#let code-window(content, filename: none, is-auto: false, style: "macos") = {
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
        box(width: 0.6em, height: 0.6em, align(horizon, line(length: 100%))),
        // Maximise (square)
        box(width: 0.6em, height: 0.6em, stroke: 1pt + muted-colour),
        // Close (x)
        box(width: 0.6em, height: 0.6em, {
          place(line(start: (0%, 0%), end: (100%, 100%)))
          place(line(start: (100%, 0%), end: (0%, 100%)))
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
    width: 100%,
    stroke: 1pt + border-colour,
    radius: 8pt,
    clip: true,
    {
      block(
        width: 100%,
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
          width: 100%,
          inset: 8pt,
          radius: 0pt,
          stroke: none,
          above: 0pt,
          below: 0pt,
        )
        show raw.where(block: true): set block(
          fill: none,
          width: 100%,
          radius: 0pt,
          stroke: none,
          above: 0pt,
          below: 0pt,
        )
        content
      }
    },
  )
}
]==]

-- ============================================================================
-- TYPST PROCESSING
-- ============================================================================

--- Process CodeBlock for Typst format.
--- Returns a block sandwich: opening RawBlock, the original CodeBlock,
--- and a closing RawBlock. Pandoc's own Typst writer handles Skylighting
--- with the document's theme automatically.
--- @param block pandoc.CodeBlock Code block element
--- @return pandoc.List|pandoc.CodeBlock Block list or original block
local function process_typst(block)
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

  if not filename then
    return block
  end

  local effective_style = block_style or CONFIG.style

  return {
    pandoc.RawBlock('typst', string.format(
      '#%s(filename: "%s", is-auto: %s, style: "%s")[',
      CONFIG.typst_wrapper,
      filename:gsub('"', '\\"'),
      is_auto and 'true' or 'false',
      effective_style
    )),
    block,
    pandoc.RawBlock('typst', ']'),
  }
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
      filename
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

  CONFIG = {
    enabled = opts['enabled'] == 'true',
    auto_filename = opts['auto-filename'] == 'true',
    style = VALID_STYLES[opts['style']] and opts['style'] or 'macos',
    typst_wrapper = opts['wrapper'],
  }

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

--- Process CodeBlock elements.
--- Typst: wraps blocks with RawBlock sandwich.
--- HTML/Reveal.js: wraps blocks with auto-filename Divs.
function CodeBlock(block)
  if not CURRENT_FORMAT or not CONFIG or not CONFIG.enabled then
    return block
  end

  if CURRENT_FORMAT == 'typst' then
    return process_typst(block)
  end

  if CURRENT_FORMAT == 'html' then
    return process_html(block)
  end

  return block
end

--- Inject Typst function definition at the start of the document.
function Pandoc(doc)
  if CURRENT_FORMAT ~= 'typst' or not CONFIG or not CONFIG.enabled then
    return doc
  end

  -- Guard: check if the function definition is already present.
  local fn_pattern = '#let ' .. CONFIG.typst_wrapper
  for _, blk in ipairs(doc.blocks) do
    if blk.t == 'RawBlock' and blk.format == 'typst'
        and blk.text:find(fn_pattern, 1, true) then
      return doc
    end
  end

  local fn_def = TYPST_FUNCTION_DEF
  if CONFIG.typst_wrapper ~= 'code-window' then
    fn_def = fn_def:gsub('#let code%-window', '#let ' .. CONFIG.typst_wrapper)
  end
  table.insert(doc.blocks, 1, pandoc.RawBlock('typst', fn_def))

  return doc
end

--- Load optional skylighting hot-fix subfilters from sibling file.
--- Kept as a single integration seam for easy future removal.
--- @return table List of subfilter tables to append
local function load_skylighting_hotfix_filters()
  local ok, result = pcall(require,
    quarto.utils.resolve_path('skylighting-typst-fix.lua'):gsub('%.lua$', ''))
  if not ok then
    utils.log_warning(EXTENSION_NAME,
      'Failed to load optional skylighting hot-fix: ' .. tostring(result))
    return {}
  end
  if type(result) ~= 'table' then
    utils.log_warning(EXTENSION_NAME,
      'Skylighting hot-fix did not return a filter list.')
    return {}
  end
  return result
end

-- ============================================================================
-- FILTER EXPORTS
-- ============================================================================

local filters = {
  { Meta = Meta },
  { Pandoc = Pandoc },
  { CodeBlock = CodeBlock },
}

for _, subfilter in ipairs(load_skylighting_hotfix_filters()) do
  table.insert(filters, subfilter)
end

return filters
