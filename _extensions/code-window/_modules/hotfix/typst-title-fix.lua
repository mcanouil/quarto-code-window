--- @module typst-title-fix
--- @license MIT
--- @copyright 2026 Mickaël Canouil
--- @author Mickaël Canouil
--- @brief Hot-fix for Quarto rendering theorem titles as string parameters.
--- Quarto renders custom type titles as title: "..." (string mode) which
--- stringifies any Typst markup. This filter injects a Typst show rule
--- that evaluates string titles as markup so inline code and other
--- formatting render correctly in theorem/example titles.

--- Typst code that overrides simple-theorem-render to evaluate string
--- titles as Typst markup. Injected after the template definitions so
--- the override replaces the default. The make-frame calls are then
--- re-created with the fixed render function.
local TYPST_TITLE_FIX = [==[
// code-window: hot-fix for Quarto rendering theorem titles as strings.
// Redefine simple-theorem-render to evaluate string titles as Typst markup.
// This produces title: [...] semantics even though Quarto emits title: "...".
#let simple-theorem-render(prefix: none, title: "", full-title: auto, body) = {
  if full-title != "" and full-title != auto and full-title != none {
    let rendered-title = if type(full-title) == str {
      eval(full-title, mode: "markup")
    } else {
      full-title
    }
    strong[#rendered-title.]
    h(0.5em)
  }
  emph(body)
  parbreak()
}
]==]

return {
  {
    Pandoc = function(doc)
      if not quarto.doc.is_format('typst') then
        return doc
      end

      -- Only inject if there are __quarto_custom Theorem Divs in the document.
      local has_theorems = false
      local function check_blocks(blocks)
        for _, blk in ipairs(blocks) do
          if blk.t == 'Div' and blk.attributes['__quarto_custom_type'] == 'Theorem' then
            has_theorems = true
            return
          end
          if blk.t == 'Div' then
            check_blocks(blk.content)
          end
        end
      end
      check_blocks(doc.blocks)
      if not has_theorems then
        return doc
      end

      -- Guard: skip if already injected.
      for _, blk in ipairs(doc.blocks) do
        if blk.t == 'RawBlock' and blk.format == 'typst'
            and blk.text:find('code-window: hot-fix for Quarto rendering theorem titles', 1, true) then
          return doc
        end
      end

      -- Insert at the end of the preamble (before the first non-RawBlock).
      local insert_pos = 1
      for idx, blk in ipairs(doc.blocks) do
        if blk.t ~= 'RawBlock' then
          insert_pos = idx
          break
        end
      end
      table.insert(doc.blocks, insert_pos, pandoc.RawBlock('typst', TYPST_TITLE_FIX))
      return doc
    end,
  },
}
