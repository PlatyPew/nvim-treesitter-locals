local api = vim.api
local ts = vim.treesitter
local locals = require('nvim-treesitter-locals.locals')

local M = {}

--- Check if any attached LSP client supports a given method.
---@param bufnr integer
---@param method string
---@return boolean
local function lsp_supports(bufnr, method)
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  for _, client in ipairs(clients) do
    if client:supports_method(method, bufnr) then
      return true
    end
  end
  return false
end

--- Rename the symbol under the cursor using treesitter locals (no LSP).
---@param bufnr? integer
function M.smart_rename_ts(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  local node = ts.get_node()
  if not node then
    return
  end

  local def_node, scope, kind = locals.find_definition(node, bufnr)
  if not kind then
    vim.notify('nvim-treesitter-locals: no definition found', vim.log.levels.WARN)
    return
  end

  local current_name = ts.get_node_text(def_node, bufnr)

  vim.ui.input({ prompt = 'New name: ', default = current_name }, function(new_name)
    if not new_name or #new_name == 0 or new_name == current_name then
      return
    end

    -- Collect all nodes to rename: definition + usages
    local usages = locals.find_usages(def_node, scope, bufnr)
    local nodes = { def_node }
    local seen = { [def_node:id()] = true }

    for _, usage in ipairs(usages) do
      if not seen[usage:id()] then
        table.insert(nodes, usage)
        seen[usage:id()] = true
      end
    end

    -- Build LSP text edits (sorted bottom-up to preserve positions)
    table.sort(nodes, function(a, b)
      local ar, ac = a:range()
      local br, bc = b:range()
      if ar ~= br then
        return ar > br
      end
      return ac > bc
    end)

    local edits = {} ---@type lsp.TextEdit[]
    for _, n in ipairs(nodes) do
      local sr, sc, er, ec = n:range()
      table.insert(edits, {
        range = {
          start = { line = sr, character = sc },
          ['end'] = { line = er, character = ec },
        },
        newText = new_name,
      })
    end

    vim.lsp.util.apply_text_edits(edits, bufnr, 'utf-8')
  end)
end

--- Rename the symbol under the cursor.
--- Uses LSP if available, falls back to treesitter.
---@param bufnr? integer
function M.smart_rename(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  if lsp_supports(bufnr, 'textDocument/rename') then
    vim.lsp.buf.rename()
    return
  end

  M.smart_rename_ts(bufnr)
end

return M
