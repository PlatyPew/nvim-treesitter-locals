local api = vim.api
local ts = vim.treesitter
local locals = require('nvim-treesitter-locals.locals')

local M = {}

--- Check if any attached LSP client supports a given method.
---@param bufnr integer
---@param method string
---@return boolean
local function lsp_supports(bufnr, method)
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    if client:supports_method(method, bufnr) then
      return true
    end
  end
  return false
end

--- Try LSP goto-definition. Returns true if LSP handled it.
---@param bufnr integer
---@return boolean
local function try_lsp_definition(bufnr)
  if not lsp_supports(bufnr, 'textDocument/definition') then
    return false
  end
  local params = vim.lsp.util.make_position_params()
  local results = vim.lsp.buf_request_sync(bufnr, 'textDocument/definition', params, 1000)
  if not results then
    return false
  end
  for _, res in pairs(results) do
    if res.result and not vim.tbl_isempty(res.result) then
      vim.lsp.buf.definition()
      return true
    end
  end
  return false
end

--- Check if a definition kind represents a file-scope symbol
--- (functions, macros, types whose usages may span the whole file).
---@param kind string
---@return boolean
local function is_file_scope_kind(kind)
  return kind:match('%.function$') or kind:match('%.macro$') or kind:match('%.type$')
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
--- When cross_file is enabled, shows definitions in Snacks.picker.
---@param bufnr? integer
function M.goto_definition(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  if try_lsp_definition(bufnr) then
    return
  end

  local node = ts.get_node()
  if not node then
    return
  end

  local node_text = ts.get_node_text(node, bufnr)
  if not node_text or #node_text == 0 then
    return
  end

  local def_node, _, kind = locals.find_definition(node, bufnr)

  -- Cross-file: show picker with local + external definitions
  local index = require('nvim-treesitter-locals.index')
  local root, lang, file_patterns = index.resolve_xref_config(bufnr)
  if root then
    local current_file = vim.fn.resolve(api.nvim_buf_get_name(bufnr))
    local all_results = {} ---@type ExternalDefinition[]

    if kind then
      local sr, sc, er, ec = def_node:range()
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

    index.ensure_index(root, lang, file_patterns)
    vim.list_extend(all_results, index.lookup(root, node_text, current_file))

    if #all_results > 0 then
      show_location_picker(all_results, 'Definition: ' .. node_text)
    end
    return
  end

  -- No cross-file: jump to local definition directly
  if kind then
    goto_node(def_node, bufnr)
  end
end

--- Show all usages of symbol under cursor across the project.
--- Collects local buffer references + cross-file references via ripgrep + treesitter.
---@param bufnr? integer
function M.goto_implementation(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  local node = ts.get_node()
  if not node then
    return
  end

  local node_text = ts.get_node_text(node, bufnr)
  if not node_text or #node_text == 0 then
    return
  end

  local current_file = vim.fn.resolve(api.nvim_buf_get_name(bufnr))
  local all_results = {} ---@type ExternalDefinition[]
  local seen = {} ---@type table<string, boolean>

  local function seen_key(file, row, col)
    return file .. ':' .. row .. ':' .. col
  end

  -- Local buffer: collect usages (excluding the definition itself)
  local def_node, scope, kind = locals.find_definition(node, bufnr)
  if kind then
    if is_file_scope_kind(kind) then
      scope = node:tree():root()
    end

    local dr, dc = def_node:range()
    seen[seen_key(current_file, dr, dc)] = true

    for _, usage in ipairs(locals.find_usages(def_node, scope, bufnr)) do
      local ur, uc, uer, uec = usage:range()
      local key = seen_key(current_file, ur, uc)
      if not seen[key] then
        seen[key] = true
        all_results[#all_results + 1] = {
          name = node_text,
          kind = 'local.reference',
          file = current_file,
          row = ur,
          col = uc,
          end_row = uer,
          end_col = uec,
        }
      end
    end
  end

  -- Cross-file: ripgrep candidates, then treesitter parse for references only
  local index = require('nvim-treesitter-locals.index')
  local root, lang, file_patterns = index.resolve_xref_config(bufnr)
  if root then
    local project = require('nvim-treesitter-locals.project')
    local xref = require('nvim-treesitter-locals.xref')
    for _, filepath in ipairs(project.grep_files(root, node_text, file_patterns)) do
      local resolved = vim.fn.resolve(filepath)
      if resolved ~= current_file then
        for _, ref in ipairs(xref.parse_file_occurrences(resolved, lang, node_text)) do
          if ref.kind == 'local.reference' then
            all_results[#all_results + 1] = ref
          end
        end
      end
    end
  end

  if #all_results == 0 then
    return
  end

  show_location_picker(all_results, 'Implementations: ' .. node_text)
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

  if is_file_scope_kind(kind) then
    scope = node:tree():root()
  end

  local usages = locals.find_usages(def_node, scope, bufnr)

  -- Build combined list: definition + usages, deduplicated
  local nodes = { def_node } ---@type TSNode[]
  local seen = { [def_node:id()] = true } ---@type table<any, boolean>

  for _, usage in ipairs(usages) do
    if not seen[usage:id()] then
      nodes[#nodes + 1] = usage
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

  goto_node(nodes[current_idx % #nodes + 1], bufnr)
end

--- Go to the previous usage of the symbol under the cursor (with wraparound).
---@param bufnr? integer
function M.goto_previous_usage(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  local nodes, current_idx = get_usage_list(bufnr)
  if not nodes or not current_idx then
    return
  end

  goto_node(nodes[(current_idx - 2) % #nodes + 1], bufnr)
end

return M
