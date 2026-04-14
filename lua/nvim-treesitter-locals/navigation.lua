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

--- Jump cursor to a treesitter node's start position.
---@param node TSNode
---@param bufnr integer
local function goto_node(node, bufnr)
  local row, col = node:range()
  api.nvim_win_set_cursor(0, { row + 1, col })
  api.nvim_set_current_buf(bufnr)
end

--- Go to the definition of the symbol under the cursor (treesitter only).
---@param bufnr? integer
function M.goto_definition_ts(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  local node = ts.get_node()
  if not node then
    return
  end

  local def_node, _, kind = locals.find_definition(node, bufnr)
  if not kind then
    return
  end

  goto_node(def_node, bufnr)
end

--- Go to the definition of the symbol under the cursor.
--- Uses LSP if available, falls back to treesitter.
---@param bufnr? integer
function M.goto_definition(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  if lsp_supports(bufnr, 'textDocument/definition') then
    vim.lsp.buf.definition()
    return
  end

  M.goto_definition_ts(bufnr)
end

--- Collect definition + usages sorted by position, and find the current index.
---@param bufnr integer
---@return TSNode[]? nodes
---@return integer? current_idx 1-based index of cursor position
local function get_usage_list(bufnr)
  local node = ts.get_node()
  if not node then
    return
  end

  local def_node, scope, kind = locals.find_definition(node, bufnr)
  if not kind then
    return
  end

  local usages = locals.find_usages(def_node, scope, bufnr)

  -- Build combined list: definition + usages, deduplicated
  local nodes = {} ---@type TSNode[]
  local seen = {} ---@type table<any, boolean>

  -- Add definition first
  table.insert(nodes, def_node)
  seen[def_node:id()] = true

  for _, usage in ipairs(usages) do
    if not seen[usage:id()] then
      table.insert(nodes, usage)
      seen[usage:id()] = true
    end
  end

  -- Sort by position
  table.sort(nodes, function(a, b)
    local ar, ac = a:range()
    local br, bc = b:range()
    if ar ~= br then
      return ar < br
    end
    return ac < bc
  end)

  -- Find current index
  local cursor = api.nvim_win_get_cursor(0)
  local crow, ccol = cursor[1] - 1, cursor[2]

  local current_idx = 1
  for i, n in ipairs(nodes) do
    local nr, nc = n:range()
    if nr == crow and nc == ccol then
      current_idx = i
      break
    end
  end

  return nodes, current_idx
end

--- Go to the next usage of the symbol under the cursor (with wraparound).
---@param bufnr? integer
function M.goto_next_usage(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  local nodes, current_idx = get_usage_list(bufnr)
  if not nodes or not current_idx then
    return
  end

  local next_idx = current_idx % #nodes + 1
  goto_node(nodes[next_idx], bufnr)
end

--- Go to the previous usage of the symbol under the cursor (with wraparound).
---@param bufnr? integer
function M.goto_previous_usage(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  local nodes, current_idx = get_usage_list(bufnr)
  if not nodes or not current_idx then
    return
  end

  local prev_idx = (current_idx - 2) % #nodes + 1
  goto_node(nodes[prev_idx], bufnr)
end

return M
