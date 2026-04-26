-- Cross-file reference finder with Snacks.picker integration.

local ts = vim.treesitter

local M = {}

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

--- Parse a file and find all captures (definitions + references) matching a symbol.
---@param filepath string absolute path
---@param lang string treesitter language
---@param symbol_name string
---@return ExternalDefinition[]
function M.parse_file_occurrences(filepath, lang, symbol_name)
  local lines = vim.fn.readfile(filepath)
  if not lines or #lines == 0 then
    return {}
  end
  local content = table.concat(lines, '\n')

  local ok, parser = pcall(ts.get_string_parser, content, lang)
  if not ok or not parser then
    return {}
  end

  parser:parse()
  local tree = parser:trees()[1]
  if not tree then
    return {}
  end

  local query = ts.query.get(lang, 'locals')
  if not query then
    return {}
  end

  local results = {} ---@type ExternalDefinition[]
  for id, node in query:iter_captures(tree:root(), content) do
    local kind = query.captures[id]
    if kind == 'local.reference' or vim.startswith(kind, 'local.definition') then
      local name = ts.get_node_text(node, content)
      if name == symbol_name then
        local sr, sc, er, ec = node:range()
        results[#results + 1] = {
          name = name,
          kind = kind,
          file = filepath,
          row = sr,
          col = sc,
          end_row = er,
          end_col = ec,
        }
      end
    end
  end

  return results
end

--- Collect all cross-file references for a symbol using ripgrep + treesitter.
---@param root string project root
---@param lang string treesitter language
---@param file_patterns string[] glob patterns
---@param symbol_name string
---@return ExternalDefinition[]
local function collect_references(root, lang, file_patterns, symbol_name)
  local project = require('nvim-treesitter-locals.project')
  local all_refs = {} ---@type ExternalDefinition[]
  for _, filepath in ipairs(project.grep_files(root, symbol_name, file_patterns)) do
    vim.list_extend(all_refs, M.parse_file_occurrences(vim.fn.resolve(filepath), lang, symbol_name))
  end
  return all_refs
end

--- Sort references: definitions first, then by file and position.
---@param refs ExternalDefinition[]
local function sort_references(refs)
  table.sort(refs, function(a, b)
    local a_def = vim.startswith(a.kind, 'local.definition') and 0 or 1
    local b_def = vim.startswith(b.kind, 'local.definition') and 0 or 1
    if a_def ~= b_def then
      return a_def < b_def
    end
    if a.file ~= b.file then
      return a.file < b.file
    end
    if a.row ~= b.row then
      return a.row < b.row
    end
    return a.col < b.col
  end)
end

--- Build Snacks.picker items from reference results.
---@param refs ExternalDefinition[]
---@return snacks.picker.finder.Item[]
local function build_picker_items(refs)
  local items = {} ---@type snacks.picker.finder.Item[]
  for _, r in ipairs(refs) do
    local line_text = read_line(r.file, r.row + 1)
    local short_kind = r.kind:gsub('local%.definition%.?', ''):gsub('local%.reference', 'ref')
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
  return items
end

--- Find all cross-file references for the symbol under cursor.
---@param bufnr? integer
function M.find_references(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local node = ts.get_node()
  if not node then
    return
  end

  local symbol_name = ts.get_node_text(node, bufnr)
  if not symbol_name or #symbol_name == 0 then
    return
  end

  local index = require('nvim-treesitter-locals.index')
  local root, lang, file_patterns = index.resolve_xref_config(bufnr)
  if not root then
    vim.notify('nvim-treesitter-locals: cross_file not configured', vim.log.levels.INFO)
    return
  end

  local all_refs = collect_references(root, lang, file_patterns, symbol_name)
  if #all_refs == 0 then
    vim.notify('nvim-treesitter-locals: no cross-file references found', vim.log.levels.INFO)
    return
  end

  sort_references(all_refs)

  Snacks.picker({
    title = 'References: ' .. symbol_name,
    items = build_picker_items(all_refs),
    format = 'file',
    preview = 'file',
  })
end

return M
