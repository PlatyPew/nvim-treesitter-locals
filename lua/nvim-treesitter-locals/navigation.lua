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

--- Read a specific line from a file (1-based).
---@param filepath string
---@param lnum integer 1-based line number
---@return string?
local function read_line(filepath, lnum)
  local lines = vim.fn.readfile(filepath, '', lnum)
  if lines and #lines >= lnum then
    return lines[lnum]
  end
  return nil
end

--- Show cross-file results in Snacks.picker.
---@param results ExternalDefinition[]
---@param title string
local function show_location_picker(results, title)
  local items = {} ---@type snacks.picker.finder.Item[]
  for _, r in ipairs(results) do
    local line_text = read_line(r.file, r.row + 1)
    local short_kind = r.kind:gsub('local%.definition%.?', '')
    if short_kind == '' then
      short_kind = 'def'
    end
    items[#items + 1] = {
      text = r.name .. ' ' .. r.file,
      file = r.file,
      pos = { r.row + 1, r.col },
      end_pos = { r.end_row + 1, r.end_col },
      line = line_text and vim.trim(line_text) or '',
      label = short_kind,
    }
  end

  Snacks.picker({
    title = title,
    items = items,
    format = 'file',
    preview = 'file',
  })
end

--- Resolve cross-file config into root, lang, file_patterns for the index.
---@param bufnr integer
---@return string? root
---@return string? lang
---@return string[]? file_patterns
local function resolve_xref_config(bufnr)
  local config = require('nvim-treesitter-locals').get_config()
  if not config.cross_file then
    return nil, nil, nil
  end

  local opts = type(config.cross_file) == 'table' and config.cross_file or {}
  local ft = vim.bo[bufnr].filetype
  local lang = opts.lang or ts.language.get_lang(ft) or ft

  local index = require('nvim-treesitter-locals.index')
  local file_patterns = opts.file_patterns or index.lang_patterns[lang]
  if not file_patterns then
    return nil, nil, nil
  end

  local project = require('nvim-treesitter-locals.project')
  local root = project.find_root(bufnr, opts.root_markers)

  return root, lang, file_patterns
end

--- Go to the definition of the symbol under the cursor (treesitter only, local buffer).
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
--- Uses LSP if available and returns results, falls back to treesitter.
--- When cross_file is enabled, collects both local and cross-file definitions
--- and shows them in a Snacks.picker. Otherwise, jumps directly to the local definition.
---@param bufnr? integer
function M.goto_definition(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  if lsp_supports(bufnr, 'textDocument/definition') then
    local params = vim.lsp.util.make_position_params()
    local lsp_results = vim.lsp.buf_request_sync(bufnr, 'textDocument/definition', params, 1000)
    if lsp_results then
      for _, res in pairs(lsp_results) do
        if res.result and not vim.tbl_isempty(res.result) then
          vim.lsp.buf.definition()
          return
        end
      end
    end
  end

  local node = ts.get_node()
  if not node then
    return
  end

  local node_text = ts.get_node_text(node, bufnr)
  if not node_text or #node_text == 0 then
    return
  end

  -- Local definition
  local def_node, _, kind = locals.find_definition(node, bufnr)

  -- Cross-file definitions
  local xref_results = {}
  local xref_enabled = false
  local root, lang, file_patterns = resolve_xref_config(bufnr)
  if root then
    xref_enabled = true
    local index = require('nvim-treesitter-locals.index')
    local current_file = vim.fn.resolve(api.nvim_buf_get_name(bufnr))
    index.ensure_index(root, lang, file_patterns)
    xref_results = index.lookup(root, node_text, current_file)
  end

  -- When cross_file enabled, always show picker (local + cross-file defs)
  if xref_enabled then
    local all_results = {} ---@type ExternalDefinition[]

    if kind then
      local sr, sc, er, ec = def_node:range()
      local current_file = vim.fn.resolve(api.nvim_buf_get_name(bufnr))
      all_results[#all_results + 1] = {
        name = node_text,
        kind = kind,
        file = current_file,
        row = sr,
        col = sc,
        end_row = er,
        end_col = ec,
      }
    end

    vim.list_extend(all_results, xref_results)

    if #all_results > 0 then
      show_location_picker(all_results, 'Definition: ' .. node_text)
    end
    return
  end

  -- cross_file not enabled: jump to local definition directly
  if kind then
    goto_node(def_node, bufnr)
  end
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

  -- For file-scope definitions (functions, macros, types), widen the search
  -- scope to the file root so usages across all functions are found.
  -- Without this, cursor on a function definition only finds usages within
  -- that function's own scope, missing call sites in other functions.
  if kind:match('%.function$') or kind:match('%.macro$') or kind:match('%.type$') then
    scope = node:tree():root()
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
