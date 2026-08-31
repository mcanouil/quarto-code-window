--- @module "cell-output"
--- @license MIT
--- @copyright 2026 Mickaël Canouil
--- @author Mickaël Canouil
--- @brief Mark the code blocks that hold the output of an executed cell.
--- @description Quarto puts the result of an executed cell in a Div with the
--- `cell-output` classes, and the code block inside carries no language class.
--- A CodeBlock filter sees that block on its own and cannot tell it apart from
--- a fenced block written without a language. This pass marks it while the
--- parent Div is still in reach, so the language and window passes can leave it
--- alone.

local M = {}

local MARKER = 'code-window-cell-output'

local get_config = nil

--- Inject the configuration accessor.
--- Called by main.lua before any filter handler runs.
--- @param fn function Accessor returning the CodeWindowConfig table
function M.set_config(fn)
  get_config = fn
end

--- Check whether a Div holds the output of an executed cell.
--- @param div pandoc.Div
--- @return boolean
local function is_cell_output(div)
  for _, class in ipairs(div.classes) do
    if class == 'cell-output' or class:match('^cell%-output%-') then
      return true
    end
  end
  return false
end

--- Mark every code block inside a cell-output Div.
--- Does nothing when the extension is off, or when cell output is framed on
--- request through the `cell-output` option.
--- @param div pandoc.Div
--- @return pandoc.Div|nil Marked Div, or nil when the Div is left as it is
function M.Div(div)
  local config = get_config and get_config()
  if not config or not config.enabled or config.cell_output then
    return nil
  end
  if not is_cell_output(div) then
    return nil
  end
  return div:walk({
    CodeBlock = function(block)
      block.attributes[MARKER] = 'true'
      return block
    end,
  })
end

--- Check whether a code block holds the output of an executed cell.
--- @param block pandoc.CodeBlock
--- @return boolean
function M.is_marked(block)
  return block.attributes[MARKER] == 'true'
end

--- Remove the marker, so it never reaches the output document.
--- @param block pandoc.CodeBlock
function M.strip(block)
  block.attributes[MARKER] = nil
end

return M
