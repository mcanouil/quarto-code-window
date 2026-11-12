--- @module "inline-code"
--- @license MIT
--- @copyright 2026 Mickaël Canouil
--- @author Mickaël Canouil
--- @brief Background box for inline code in Typst output.
--- @description Quarto gives inline code no background in Typst. This pass puts
--- each inline Code element in a box filled with the theme background, or with
--- a tone mixed from the page when the theme gives none. The mixed tone uses the
--- colour helpers that the code-window definitions declare.

--- Shape of the box that holds inline code, after its fill.
local _inline_box_style = 'inset: (x: 3pt, y: 0pt), outset: (y: 3pt), '
    .. 'radius: 2pt, stroke: none)['

--- Process inline Code for Typst format.
--- Puts the Code element in a box that carries the theme background colour.
--- The element itself stays in the document, so Pandoc highlights it and
--- writes the token definitions for it.
--- @param el pandoc.Code Inline code element
--- @return pandoc.Inlines The boxed code
local function process_typst_inline(el)
  local hm = PANDOC_WRITER_OPTIONS and PANDOC_WRITER_OPTIONS.highlight_method
  local bg = hm and hm['background-color']
  local opening, closing

  if type(bg) == 'string' then
    opening = string.format('#box(fill: rgb("%s"), ', bg) .. _inline_box_style
    closing = ']'
  else
    opening = '#context { let _bg = _cw-page-bg(); let _f = _cw-fg(_bg); '
      .. 'box(fill: color.mix((_f, 10%), (_bg, 90%)), ' .. _inline_box_style
    closing = '] }'
  end

  return pandoc.Inlines({
    pandoc.RawInline('typst', opening),
    el,
    pandoc.RawInline('typst', closing),
  })
end

--- Walk the document tree and box inline Code with background styling.
--- The extension contributes the pass once, so it sees each Code element
--- once and boxes it once, theorem titles included. Metadata such as the
--- document title is left alone: the template writes it before the
--- definitions the box relies on.
local function process_inline_code(doc)
  if not quarto.doc.is_format('typst') then
    return doc
  end
  doc.blocks = doc.blocks:walk({ Code = process_typst_inline })
  return doc
end

return {
  Pandoc = process_inline_code,
}
