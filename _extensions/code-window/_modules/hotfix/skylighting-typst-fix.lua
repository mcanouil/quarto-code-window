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

local _wrapper_prefix = 'code-window'

--- Set the wrapper prefix for Typst function name generation.
--- Called by main.lua before each handler invocation.
--- @param prefix string The wrapper prefix (e.g. 'code-window' or 'my-window')
local function set_wrapper(prefix)
  _wrapper_prefix = prefix
end

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

  local circled = _wrapper_prefix .. '-circled-number'
  return string.format([==[
// skylighting-typst-fix override
#let Skylighting(
  fill: none,
  number: false,
  start: 1,
  sourcelines,
) = {
  let bgcolor = if fill != none { fill } else { rgb("%s") }
  let has-gutter = start + sourcelines.len() > 999

  context {
    let annot-data = _cw-annotations.get()
    let blocks = []
    let lnum = start - 1
    let seen-annotes = (:)

    for ln in sourcelines {
      lnum = lnum + 1
      if number {
        blocks = blocks + box(
          width: if has-gutter { 30pt } else { 24pt },
          text([ #lnum ]),
        )
      }

      if annot-data != none {
        let annot-num = annot-data.annotations.at(str(lnum), default: none)
        if annot-num != none {
          let lbl-prefix = "cw-" + str(annot-data.block-id) + "-"
          if str(annot-num) not in seen-annotes {
            seen-annotes.insert(str(annot-num), true)
            blocks = blocks + box(width: 100%%)[
              #ln
              #h(1fr)
              #link(label(lbl-prefix + "item-" + str(annot-num)))[
                #%s(annot-num, bg-colour: annot-data.bg-colour)
              ]
              #label(lbl-prefix + "line-" + str(annot-num))
            ]
          } else {
            blocks = blocks + box(width: 100%%)[
              #ln
              #h(1fr)
              #link(label(lbl-prefix + "item-" + str(annot-num)))[
                #%s(annot-num, bg-colour: annot-data.bg-colour)
              ]
            ]
          }
        } else {
          blocks = blocks + ln
        }
      } else {
        blocks = blocks + ln
      }
      blocks = blocks + EndLine()
    }

    block(
      fill: bgcolor,
      width: 100%%,
      inset: 8pt,
      radius: 2pt,
      stroke: 0.5pt + luma(200),
      blocks,
    )
  }
}
]==], bg, circled, circled)
end

--- Build a show raw.line rule for annotation support in idiomatic mode.
--- When Skylighting is not available (idiomatic/native Typst highlighting),
--- this rule reads _cw-annotations state and adds circled annotation markers
--- to annotated lines, mirroring what the Skylighting override does.
--- @return string Typst show rule definition
local function build_raw_line_annotation_rule()
  local circled = _wrapper_prefix .. '-circled-number'
  return string.format([==[
// idiomatic-mode annotation support for raw blocks
#show raw.line: it => {
  context {
    let annot-data = _cw-annotations.get()
    if annot-data == none {
      it
    } else {
      let annot-num = annot-data.annotations.at(str(it.number), default: none)
      if annot-num == none {
        it
      } else {
        let lbl-prefix = "cw-" + str(annot-data.block-id) + "-"
        let first-line = calc.min(
          ..annot-data.annotations.pairs()
            .filter(p => p.at(1) == annot-num)
            .map(p => int(p.at(0)))
        )
        if it.number == first-line {
          box(width: 100%%)[
            #it
            #h(1fr)
            #link(label(lbl-prefix + "item-" + str(annot-num)))[
              #%s(annot-num, bg-colour: annot-data.bg-colour)
            ]
            #label(lbl-prefix + "line-" + str(annot-num))
          ]
        } else {
          box(width: 100%%)[
            #it
            #h(1fr)
            #link(label(lbl-prefix + "item-" + str(annot-num)))[
              #%s(annot-num, bg-colour: annot-data.bg-colour)
            ]
          ]
        }
      }
    }
  }
}
]==], circled, circled)
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
--- Always injected when code-window is enabled to support annotation markers.
function Pandoc(doc)
  if not quarto.doc.is_format('typst') then
    return doc
  end

  -- Guard: skip if override or annotation rule already injected.
  for _, blk in ipairs(doc.blocks) do
    if blk.t == 'RawBlock' and blk.format == 'typst'
        and (blk.text:find('// skylighting-typst-fix override', 1, true)
          or blk.text:find('// idiomatic-mode annotation support', 1, true)) then
      return doc
    end
  end

  local override = build_skylighting_override()
  local rule = override or build_raw_line_annotation_rule()

  -- Insert after the code-window function definitions so the override/rule can
  -- reference _cw-annotations and the wrapper-prefixed circled-number function.
  local insert_pos = 1
  for idx, blk in ipairs(doc.blocks) do
    if blk.t == 'RawBlock' and blk.format == 'typst'
        and blk.text:find('_cw%-annotations') then
      insert_pos = idx + 1
      break
    end
  end
  table.insert(doc.blocks, insert_pos, pandoc.RawBlock('typst', rule))
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
  set_wrapper = set_wrapper,
  filters = {
    { Pandoc = Pandoc },
    { Code = Code },
  },
}
