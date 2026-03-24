--- @module typst-title-fix
--- @license MIT
--- @copyright 2026 Mickaël Canouil
--- @author Mickaël Canouil
--- @brief Hot-fix for Quarto rendering theorem titles as string parameters.
--- Quarto renders custom type titles as title: "..." (string mode) which
--- stringifies any Typst markup. This post-quarto filter scans the Typst
--- preamble for make-frame definitions, then injects wrapper functions that
--- evaluate string titles as Typst markup via eval(mode: "markup").

--- Typst wrapper template. %s is replaced with the function name.
local WRAPPER_TEMPLATE = [==[
#let _cw-orig-%s = %s
#let %s(title: none, ..args) = {
  let t = if title != none and type(title) == str {
    eval(title, mode: "markup")
  } else {
    title
  }
  _cw-orig-%s(title: t, ..args)
}
]==]

--- Build Typst code that wraps each theorem function to eval string titles.
--- @param func_names table List of function names to wrap
--- @return string Typst code
local function build_wrappers(func_names)
  local parts = { '// code-window: hot-fix for Quarto rendering theorem titles as strings.' }
  for _, name in ipairs(func_names) do
    table.insert(parts, string.format(WRAPPER_TEMPLATE, name, name, name, name))
  end
  return table.concat(parts, '\n')
end

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

      -- Scan preamble RawBlocks for make-frame definitions to find function names.
      -- Pattern: #let (xxx-counter, xxx-box, xxx, show-xxx) = make-frame(
      local func_names = {}
      for _, blk in ipairs(doc.blocks) do
        if blk.t == 'RawBlock' and blk.format == 'typst' then
          for name in blk.text:gmatch('#let %([%w%-]+%-counter, [%w%-]+%-box, ([%w%-]+), show%-[%w%-]+%) = make%-frame%(') do
            table.insert(func_names, name)
          end
        end
      end

      if #func_names == 0 then
        return doc
      end

      -- Insert wrappers after the last make-frame definition.
      local insert_pos = 1
      for idx, blk in ipairs(doc.blocks) do
        if blk.t == 'RawBlock' and blk.format == 'typst'
            and blk.text:find('make%-frame%(') then
          insert_pos = idx + 1
        end
      end
      table.insert(doc.blocks, insert_pos, pandoc.RawBlock('typst', build_wrappers(func_names)))
      return doc
    end,
  },
}
