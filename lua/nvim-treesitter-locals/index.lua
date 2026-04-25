-- Cross-file symbol index with persistent caching.
-- Builds an inverted index (symbol → locations) on first use.
-- Incrementally updates via mtime checks — only re-parses changed files.
-- Persists to disk so cache survives neovim restart.

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

---@class FileEntry
---@field mtime number File modification time
---@field defs ExternalDefinition[]

---@class ProjectIndex
---@field root string Project root path
---@field lang string Treesitter language
---@field file_patterns string[] Glob patterns used
---@field files table<string, FileEntry> Per-file tracking
---@field symbols table<string, ExternalDefinition[]> Inverted index

local CACHE_VERSION = 1

--- Known file extensions per treesitter language.
M.lang_patterns = {
  c = { '*.c', '*.h' },
  cpp = { '*.cpp', '*.hpp', '*.cc', '*.hh', '*.cxx', '*.hxx', '*.h' },
  python = { '*.py' },
  javascript = { '*.js', '*.jsx', '*.mjs' },
  typescript = { '*.ts', '*.tsx' },
  lua = { '*.lua' },
  rust = { '*.rs' },
  go = { '*.go' },
  java = { '*.java' },
  zig = { '*.zig' },
}

--- In-memory index cache, keyed by project root.
---@type table<string, ProjectIndex>
local indexes = {}

--- Get deterministic cache file path for a project root.
---@param root string
---@return string
local function cache_path(root)
  local cache_dir = vim.fn.stdpath('cache') .. '/nvim-treesitter-locals'
  -- Sanitize root path for filename: replace / with %%
  local safe = root:gsub('/', '%%')
  return cache_dir .. '/' .. safe .. '.json'
end

--- Parse a file from disk and extract all definition captures.
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

--- Build inverted symbol table from file entries.
---@param index ProjectIndex
local function build_symbol_table(index)
  local symbols = {} ---@type table<string, ExternalDefinition[]>
  for _, entry in pairs(index.files) do
    for _, def in ipairs(entry.defs) do
      if not symbols[def.name] then
        symbols[def.name] = {}
      end
      symbols[def.name][#symbols[def.name] + 1] = def
    end
  end
  index.symbols = symbols
end

--- Load index from disk cache.
---@param root string
---@return ProjectIndex?
local function load_disk_cache(root)
  local path = cache_path(root)
  local ok_stat, stat = pcall(vim.uv.fs_stat, path)
  if not ok_stat or not stat then
    return nil
  end

  local ok_read, content = pcall(vim.fn.readfile, path)
  if not ok_read or not content or #content == 0 then
    return nil
  end

  local raw = table.concat(content, '\n')
  local ok_decode, data = pcall(vim.json.decode, raw)
  if not ok_decode or not data then
    return nil
  end

  if data.version ~= CACHE_VERSION then
    return nil
  end

  -- Reconstruct index
  ---@type ProjectIndex
  local index = {
    root = data.root,
    lang = data.lang,
    file_patterns = data.file_patterns,
    files = {},
    symbols = {},
  }

  -- Rebuild file entries with proper ExternalDefinition objects
  for filepath, file_data in pairs(data.files or {}) do
    local defs = {} ---@type ExternalDefinition[]
    for _, d in ipairs(file_data.defs or {}) do
      defs[#defs + 1] = {
        name = d.name,
        kind = d.kind,
        file = filepath,
        row = d.row,
        col = d.col,
        end_row = d.end_row,
        end_col = d.end_col,
      }
    end
    index.files[filepath] = {
      mtime = file_data.mtime,
      defs = defs,
    }
  end

  build_symbol_table(index)
  return index
end

--- Save index to disk cache.
---@param index ProjectIndex
local function save_disk_cache(index)
  local path = cache_path(index.root)
  local dir = vim.fn.fnamemodify(path, ':h')

  -- Ensure cache directory exists
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, 'p')
  end

  -- Build serializable structure (strip file field from defs to save space)
  local files = {}
  for filepath, entry in pairs(index.files) do
    local defs = {}
    for _, d in ipairs(entry.defs) do
      defs[#defs + 1] = {
        name = d.name,
        kind = d.kind,
        row = d.row,
        col = d.col,
        end_row = d.end_row,
        end_col = d.end_col,
      }
    end
    files[filepath] = {
      mtime = entry.mtime,
      defs = defs,
    }
  end

  local data = {
    version = CACHE_VERSION,
    root = index.root,
    lang = index.lang,
    file_patterns = index.file_patterns,
    files = files,
  }

  local ok, json = pcall(vim.json.encode, data)
  if ok and json then
    vim.fn.writefile({ json }, path)
  end
end

--- Get mtime for a file, or nil if it doesn't exist.
---@param filepath string
---@return number?
local function get_mtime(filepath)
  local ok, stat = pcall(vim.uv.fs_stat, filepath)
  if ok and stat then
    return stat.mtime.sec + stat.mtime.nsec / 1e9
  end
  return nil
end

--- Incrementally update an existing index.
--- Stats known files (detect modified/deleted), globs for new files.
--- Only re-parses files that actually changed.
---@param index ProjectIndex
local function update_index(index)
  local dirty = false

  -- 1. Check known files for modifications and deletions
  local to_remove = {} ---@type string[]
  local to_reparse = {} ---@type string[]

  for filepath, entry in pairs(index.files) do
    local mtime = get_mtime(filepath)
    if not mtime then
      -- File deleted
      to_remove[#to_remove + 1] = filepath
    elseif mtime ~= entry.mtime then
      -- File modified
      to_reparse[#to_reparse + 1] = filepath
    end
  end

  -- Remove deleted files
  for _, filepath in ipairs(to_remove) do
    index.files[filepath] = nil
    dirty = true
  end

  -- Re-parse modified files
  for _, filepath in ipairs(to_reparse) do
    local mtime = get_mtime(filepath)
    local defs = M.parse_file_definitions(filepath, index.lang)
    index.files[filepath] = { mtime = mtime, defs = defs }
    dirty = true
  end

  -- 2. Glob for new files
  local all_files = project.list_files(index.root, index.file_patterns)
  for _, filepath in ipairs(all_files) do
    local resolved = vim.fn.resolve(filepath)
    if not index.files[resolved] then
      local mtime = get_mtime(resolved)
      if mtime then
        local defs = M.parse_file_definitions(resolved, index.lang)
        index.files[resolved] = { mtime = mtime, defs = defs }
        dirty = true
      end
    end
  end

  -- Rebuild symbol table if anything changed
  if dirty then
    build_symbol_table(index)
    save_disk_cache(index)
  end
end

--- Cold build: parse all project files from scratch.
---@param root string
---@param lang string
---@param file_patterns string[]
---@return ProjectIndex
local function cold_build(root, lang, file_patterns)
  ---@type ProjectIndex
  local index = {
    root = root,
    lang = lang,
    file_patterns = file_patterns,
    files = {},
    symbols = {},
  }

  local all_files = project.list_files(root, file_patterns)
  for _, filepath in ipairs(all_files) do
    local resolved = vim.fn.resolve(filepath)
    local mtime = get_mtime(resolved)
    if mtime then
      local defs = M.parse_file_definitions(resolved, lang)
      index.files[resolved] = { mtime = mtime, defs = defs }
    end
  end

  build_symbol_table(index)
  save_disk_cache(index)
  return index
end

--- Ensure index is built and up-to-date for a project root.
--- Lazy: does nothing until first call. Incremental after.
---@param root string
---@param lang string
---@param file_patterns string[]
---@return ProjectIndex
function M.ensure_index(root, lang, file_patterns)
  -- 1. In-memory cache hit
  if indexes[root] then
    update_index(indexes[root])
    return indexes[root]
  end

  -- 2. Disk cache hit
  local cached = load_disk_cache(root)
  if cached then
    -- Verify lang/patterns match — if config changed, rebuild
    if cached.lang == lang then
      indexes[root] = cached
      update_index(cached)
      return cached
    end
  end

  -- 3. Cold build
  local index = cold_build(root, lang, file_patterns)
  indexes[root] = index
  return index
end

--- Look up a symbol in the cached index.
--- Returns definitions from all files except current_file.
---@param root string
---@param symbol_name string
---@param current_file string resolved absolute path of current buffer
---@return ExternalDefinition[]
function M.lookup(root, symbol_name, current_file)
  local index = indexes[root]
  if not index or not index.symbols[symbol_name] then
    return {}
  end

  local results = {} ---@type ExternalDefinition[]
  for _, def in ipairs(index.symbols[symbol_name]) do
    if def.file ~= current_file then
      results[#results + 1] = def
    end
  end

  -- Prioritize function definitions
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

--- Clear index cache (in-memory and disk).
---@param root? string specific root to clear, or nil for all
function M.clear(root)
  if root then
    indexes[root] = nil
    local path = cache_path(root)
    if vim.fn.filereadable(path) == 1 then
      vim.fn.delete(path)
    end
  else
    for r, _ in pairs(indexes) do
      local path = cache_path(r)
      if vim.fn.filereadable(path) == 1 then
        vim.fn.delete(path)
      end
    end
    indexes = {}
  end
end

--- Force rebuild index for a project root.
---@param root string
---@param lang string
---@param file_patterns string[]
---@return ProjectIndex
function M.rebuild(root, lang, file_patterns)
  indexes[root] = nil
  local path = cache_path(root)
  if vim.fn.filereadable(path) == 1 then
    vim.fn.delete(path)
  end
  return M.ensure_index(root, lang, file_patterns)
end

return M
