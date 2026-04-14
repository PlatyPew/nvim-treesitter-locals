local api = vim.api
local ts = vim.treesitter
local locals = require('nvim-treesitter-locals.locals')

local M = {}

local ns = api.nvim_create_namespace('nvim-treesitter-locals-highlight')
local augroup_name = 'NvimTreesitterLocalsHighlight'
local enabled_bufs = {} ---@type table<integer, boolean>
local last_node = {} ---@type table<integer, any> bufnr -> node id

--- Highlight the definition and all usages of the symbol under the cursor.
---@param bufnr? integer
function M.highlight_definitions(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  local node = ts.get_node()
  if not node then
    return
  end

  -- Skip if we already highlighted this exact node
  local node_id = node:id()
  if last_node[bufnr] == node_id then
    return
  end

  M.clear_highlights(bufnr)
  last_node[bufnr] = node_id

  local node_text = ts.get_node_text(node, bufnr)
  if not node_text or #node_text == 0 then
    return
  end

  local def_node, scope, kind = locals.find_definition(node, bufnr)
  if not kind then
    return
  end

  -- Highlight the definition
  local sr, sc, er, ec = def_node:range()
  api.nvim_buf_set_extmark(bufnr, ns, sr, sc, {
    end_row = er,
    end_col = ec,
    hl_group = 'TSDefinition',
    priority = 200,
  })

  -- Highlight all usages
  local usages = locals.find_usages(def_node, scope, bufnr)
  for _, usage_node in ipairs(usages) do
    local ur, uc, uer, uec = usage_node:range()
    api.nvim_buf_set_extmark(bufnr, ns, ur, uc, {
      end_row = uer,
      end_col = uec,
      hl_group = 'TSDefinitionUsage',
      priority = 200,
    })
  end
end

--- Clear all definition/usage highlights in the buffer.
---@param bufnr? integer
function M.clear_highlights(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  last_node[bufnr] = nil
end

--- Enable automatic highlight of definitions on CursorHold for a buffer.
---@param bufnr? integer
function M.enable(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  if enabled_bufs[bufnr] then
    return
  end
  enabled_bufs[bufnr] = true

  local group = api.nvim_create_augroup(augroup_name .. bufnr, { clear = true })

  api.nvim_create_autocmd('CursorHold', {
    group = group,
    buffer = bufnr,
    callback = function()
      M.highlight_definitions(bufnr)
    end,
  })

  api.nvim_create_autocmd({ 'CursorMoved', 'InsertEnter' }, {
    group = group,
    buffer = bufnr,
    callback = function()
      M.clear_highlights(bufnr)
    end,
  })

  api.nvim_create_autocmd('BufDelete', {
    group = group,
    buffer = bufnr,
    callback = function()
      enabled_bufs[bufnr] = nil
      last_node[bufnr] = nil
    end,
  })
end

--- Disable automatic highlight of definitions for a buffer.
---@param bufnr? integer
function M.disable(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  if not enabled_bufs[bufnr] then
    return
  end

  enabled_bufs[bufnr] = nil
  last_node[bufnr] = nil
  M.clear_highlights(bufnr)
  api.nvim_create_augroup(augroup_name .. bufnr, { clear = true })
end

--- Toggle automatic highlight of definitions for a buffer.
---@param bufnr? integer
function M.toggle(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  if enabled_bufs[bufnr] then
    M.disable(bufnr)
  else
    M.enable(bufnr)
  end
end

return M
