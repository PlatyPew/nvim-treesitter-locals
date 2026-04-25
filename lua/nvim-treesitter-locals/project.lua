-- Project root detection and file discovery for cross-file operations.

local M = {}

local root_cache = {} ---@type table<string, string>

--- Detect project root for a buffer.
--- Walks up from buffer directory looking for root markers, falls back to cwd.
---@param bufnr integer
---@param root_markers? string[]
---@return string root Absolute path to project root
function M.find_root(bufnr, root_markers)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local buf_dir = bufname ~= '' and vim.fn.fnamemodify(vim.fn.resolve(bufname), ':h')
    or vim.fn.resolve(vim.fn.getcwd())

  if root_cache[buf_dir] then
    return root_cache[buf_dir]
  end

  root_markers = root_markers or { '.git', 'Makefile', 'compile_commands.json' }

  local found = vim.fs.find(root_markers, { upward = true, path = buf_dir })[1]
  if found then
    local root = vim.fn.resolve(vim.fn.fnamemodify(found, ':h'))
    root_cache[buf_dir] = root
    return root
  end

  -- No root markers found — use buffer's directory as project root.
  -- This works well for IDA decompiled projects that lack .git.
  local root = buf_dir
  root_cache[buf_dir] = root
  return root
end

--- List all project files matching given glob patterns.
---@param root string project root path
---@param file_patterns string[] glob patterns (e.g. {"*.c", "*.h"})
---@return string[] file_paths absolute paths
function M.list_files(root, file_patterns)
  local files = {} ---@type string[]
  local seen = {} ---@type table<string, boolean>

  for _, pattern in ipairs(file_patterns) do
    local matches = vim.fn.globpath(root, '**/' .. pattern, false, true)
    for _, f in ipairs(matches) do
      if not seen[f] then
        seen[f] = true
        files[#files + 1] = f
      end
    end
  end

  return files
end

--- Narrow file candidates using ripgrep or grep.
--- Returns files containing the symbol text.
---@param root string project root
---@param symbol_name string symbol to search for
---@param file_patterns string[] glob patterns for file filtering
---@return string[] matching_files
function M.grep_files(root, symbol_name, file_patterns)
  if vim.fn.executable('rg') == 1 then
    local cmd = { 'rg', '--files-with-matches', '--fixed-strings', symbol_name }
    for _, pattern in ipairs(file_patterns) do
      cmd[#cmd + 1] = '--glob'
      cmd[#cmd + 1] = pattern
    end
    cmd[#cmd + 1] = root

    local result = vim.fn.systemlist(cmd)
    if vim.v.shell_error == 0 and result and #result > 0 then
      -- Resolve symlinks for consistent path comparison
      for i, f in ipairs(result) do
        result[i] = vim.fn.resolve(f)
      end
      return result
    end
    return {}
  end

  if vim.fn.executable('grep') == 1 then
    local cmd = { 'grep', '-rl', '--fixed-strings', symbol_name, root }
    local result = vim.fn.systemlist(cmd)
    if vim.v.shell_error == 0 and result and #result > 0 then
      -- Filter by file patterns manually
      local filtered = {}
      for _, f in ipairs(result) do
        for _, pattern in ipairs(file_patterns) do
          local ext = pattern:match('%.(%w+)$')
          if ext and f:match('%.' .. ext .. '$') then
            filtered[#filtered + 1] = f
            break
          end
        end
      end
      return filtered
    end
    return {}
  end

  -- Fallback: return all files (no pre-filtering)
  return M.list_files(root, file_patterns)
end

--- Clear the root cache (useful for testing or when project structure changes).
function M.clear_cache()
  root_cache = {}
end

return M
