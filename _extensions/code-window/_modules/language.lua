--- @module "language"
--- @license MIT
--- @copyright 2026 Mickaël Canouil
--- @author Mickaël Canouil
--- @brief Normalise code blocks with no or unknown language class.

local cell_output = require(
  quarto.utils.resolve_path('_modules/cell-output.lua'):gsub('%.lua$', ''))

local M = {}

local known_language_cache = {}

--- Check if a language is recognised by Pandoc's syntax highlighter.
--- Renders a test CodeBlock to HTML and checks for the sourceCode class.
--- @param lang string Language identifier
--- @return boolean
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

--- Write the label on a block that has no name yet.
--- A filename or a label already on the block wins, because the author or
--- another filter set it to name the window.
--- @param block pandoc.CodeBlock
--- @param label string Label to write when the block has no name yet
local function set_label(block, label)
  local attributes = block.attributes
  local has_filename = attributes['filename'] and attributes['filename'] ~= ''
  local has_label = attributes['code-window-auto-label'] and attributes['code-window-auto-label'] ~= ''
  if not has_filename and not has_label then
    attributes['code-window-auto-label'] = label
  end
end

--- Normalise code blocks with no or unknown language class to "default".
--- Both are framed like a highlighted code cell rather than left as a bare
--- block: a no-language block is labelled "default", and an unknown language
--- keeps its original token as the label. The label is carried on the
--- `code-window-auto-label` attribute (not `filename`, which is reserved for
--- author-set filenames) and consumed by the auto-filename windowing path.
--- The output of an executed cell is left as Quarto wrote it.
--- @param block pandoc.CodeBlock
--- @return pandoc.CodeBlock|nil
function M.CodeBlock(block)
  if cell_output.is_marked(block) then
    return nil
  end

  if not block.classes or #block.classes == 0 then
    block.classes:insert('default')
    set_label(block, 'default')
    return block
  end

  local lang = block.classes[1]
  if not is_known_language(lang) then
    block.classes[1] = 'default'
    set_label(block, lang)
  end

  return block
end

return M
