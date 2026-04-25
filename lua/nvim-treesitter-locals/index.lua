-- Cross-file symbol index.
-- Parses external files with treesitter string parser (no buffer creation)
-- and extracts definitions for cross-file goto-definition.

local ts = vim.treesitter
local project = require('nvim-treesitter-locals.project')

local M = {}

---@class ExternalDefinition
---@field name string Symbol text
---@field kind string Capture kind (e.g. "local.definition.function")
---@field file string Absolute file path
---@field row integer 0-based row
---@field col integer 0-based column
---@field end_row integer 0-based end row
---@field end_col integer 0-based end column

--- Parse a file from disk and extract all definition captures.
--- Uses string parser — no Neovim buffer created.
---@param filepath string absolute path
---@param lang string treesitter language
---@return ExternalDefinition[]
function M.parse_file_definitions(filepath, lang)
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
  local root = tree:root()

  local query = ts.query.get(lang, 'locals')
  if not query then
    return {}
  end

  local definitions = {} ---@type ExternalDefinition[]
  for id, node in query:iter_captures(root, content) do
    local kind = query.captures[id]
    if vim.startswith(kind, 'local.definition') then
      local sr, sc, er, ec = node:range()
      local name = ts.get_node_text(node, content)
      if name and #name > 0 then
        definitions[#definitions + 1] = {
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

  return definitions
end

--- Search for a symbol definition across project files.
--- Flow: find root → grep to narrow candidates → parse each → filter by name.
---@param symbol_name string
---@param bufnr integer current buffer
---@param opts? { lang?: string, file_patterns?: string[], root_markers?: string[] }
---@return ExternalDefinition[]
function M.find_external_definition(symbol_name, bufnr, opts)
  if type(opts) ~= 'table' then
    opts = {}
  end
  local ft = vim.bo[bufnr].filetype
  local lang = opts.lang or ts.language.get_lang(ft) or ft
  local file_patterns = opts.file_patterns or { '*.c', '*.h' }
  local root = project.find_root(bufnr, opts.root_markers)

  local current_file = vim.fn.resolve(vim.api.nvim_buf_get_name(bufnr))
  local candidates = project.grep_files(root, symbol_name, file_patterns)

  local results = {} ---@type ExternalDefinition[]
  for _, filepath in ipairs(candidates) do
    -- Skip current buffer's file
    if filepath ~= current_file then
      local defs = M.parse_file_definitions(filepath, lang)
      for _, def in ipairs(defs) do
        if def.name == symbol_name then
          results[#results + 1] = def
        end
      end
    end
  end

  -- Prioritize function definitions (most common cross-file target)
  table.sort(results, function(a, b)
    local a_fn = a.kind == 'local.definition.function' and 0 or 1
    local b_fn = b.kind == 'local.definition.function' and 0 or 1
    if a_fn ~= b_fn then
      return a_fn < b_fn
    end
    return a.file < b.file
  end)

  return results
end

return M
