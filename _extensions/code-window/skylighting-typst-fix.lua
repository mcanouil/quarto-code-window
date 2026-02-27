--- @module skylighting-typst-fix
--- @license MIT
--- @copyright 2026 Mickaël Canouil
--- @author Mickaël Canouil
--- @brief Typst skylighting styling override and inline code background.
--- Pandoc 3.8+ generates correct token colours and bgcolor from the theme,
--- but the generated Skylighting block lacks styling properties (width, inset,
--- radius, stroke) and ignores its own fill parameter. This module overrides
--- the Skylighting function with better block styling and adds inline code
--- background support for Typst output.

--- Build a Skylighting override with improved block styling.
--- Pandoc 3.8+ generates correct bgcolor but the block call lacks width,
--- inset, radius, and stroke properties. The fill parameter is also ignored.
--- This override fixes both issues.
--- @return string|nil Typst #let Skylighting(...) definition, or nil
local function build_skylighting_override()
  local hm = PANDOC_WRITER_OPTIONS and PANDOC_WRITER_OPTIONS.highlight_method
  if not hm then return nil end

  local bg = hm['background-color']
  if not bg or type(bg) ~= 'string' then return nil end

  return string.format([==[
// skylighting-typst-fix override
#let Skylighting(
  fill: none,
  number: false,
  start: 1,
  sourcelines,
) = {
  let bgcolor = if fill != none { fill } else { rgb("%s") }
  let blocks = []
  let lnum = start - 1
  let has-gutter = start + sourcelines.len() > 999

  for ln in sourcelines {
    if number {
      lnum = lnum + 1
      blocks = blocks + box(
        width: if has-gutter { 30pt } else { 24pt },
        text([ #lnum ]),
      )
    }
    blocks = blocks + ln + EndLine()
  }

  block(
    fill: bgcolor,
    width: 100%%,
    inset: 8pt,
    radius: 2pt,
    stroke: none,
    blocks,
  )
}
]==], bg)
end

--- Process inline Code for Typst format.
--- Renders the Code element through Pandoc's Typst writer to get syntax-
--- highlighted output, then wraps it in a box with the theme background colour.
--- @param el pandoc.Code Inline code element
--- @return pandoc.RawInline|pandoc.Code Transformed or original element
local function process_typst_inline(el)
  local hm = PANDOC_WRITER_OPTIONS and PANDOC_WRITER_OPTIONS.highlight_method
  local bg_fill = 'luma(230)'
  local write_opts = nil

  if hm then
    local bg = hm['background-color']
    if bg and type(bg) == 'string' then
      bg_fill = string.format('rgb("%s")', bg)
    end
    write_opts = pandoc.WriterOptions({
      highlight_method = hm,
    })
  end

  local rendered = pandoc.write(pandoc.Pandoc({ pandoc.Plain({ el }) }), 'typst', write_opts)
  rendered = rendered:gsub('%s+$', '')
  if rendered == '' then return el end

  local typst_code = string.format(
    '#box(fill: %s, inset: (x: 3pt, y: 0pt), outset: (y: 3pt), radius: 2pt, stroke: none)[%s]',
    bg_fill,
    rendered
  )

  return pandoc.RawInline('typst', typst_code)
end

--- Inject Skylighting override at the start of the document.
function Pandoc(doc)
  if not quarto.doc.is_format('typst') then
    return doc
  end

  -- Guard: skip if override already injected.
  for _, blk in ipairs(doc.blocks) do
    if blk.t == 'RawBlock' and blk.format == 'typst'
        and blk.text:find('// skylighting-typst-fix override', 1, true) then
      return doc
    end
  end

  local override = build_skylighting_override()
  if not override then
    return doc
  end

  table.insert(doc.blocks, 1, pandoc.RawBlock('typst', override))
  return doc
end

--- Wrap inline Code elements with a background box in Typst output.
function Code(el)
  if not quarto.doc.is_format('typst') then
    return el
  end
  return process_typst_inline(el)
end

return {
  { Pandoc = Pandoc },
  { Code = Code },
}
