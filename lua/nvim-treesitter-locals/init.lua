local M = {}

---@class NvimTreesitterLocalsCrossFileOpts
---@field root_markers? string[] Project root markers (default: {".git", "Makefile", "compile_commands.json"})
---@field file_patterns? string[] File patterns to scan (default: auto-detect from language)
---@field lang? string Treesitter language override (default: auto-detect from filetype)

---@class NvimTreesitterLocalsOpts
---@field highlight_definitions? boolean Enable auto-highlight on CursorHold for all treesitter buffers (default: false)
---@field keymaps? NvimTreesitterLocalsKeymaps Keybindings (set to false to disable a default, or string to override)
---@field cross_file? NvimTreesitterLocalsCrossFileOpts|boolean Enable cross-file features (default: false). Set true for auto-detect.

---@class NvimTreesitterLocalsKeymaps
---@field goto_definition? string|false Go to definition (LSP -> treesitter fallback)
---@field goto_definition_ts? string|false Go to definition (treesitter only)
---@field goto_next_usage? string|false Next usage (wraps around)
---@field goto_previous_usage? string|false Previous usage (wraps around)
---@field smart_rename? string|false Rename symbol (LSP -> treesitter fallback)
---@field smart_rename_ts? string|false Rename symbol (treesitter only)
---@field goto_implementation? string|false Go to implementation (all usages across project)
---@field find_references_xref? string|false Find cross-file references

---@type NvimTreesitterLocalsOpts
local defaults = {
  highlight_definitions = false,
  keymaps = {},
  cross_file = false,
}

local resolved_config = nil ---@type NvimTreesitterLocalsOpts?

local keymap_actions = {
  goto_definition = {
    module = 'nvim-treesitter-locals.navigation',
    fn = 'goto_definition',
    desc = 'Go to definition',
    mode = 'n',
  },
  goto_definition_ts = {
    module = 'nvim-treesitter-locals.navigation',
    fn = 'goto_definition_ts',
    desc = 'Go to definition (treesitter)',
    mode = 'n',
  },
  goto_next_usage = {
    module = 'nvim-treesitter-locals.navigation',
    fn = 'goto_next_usage',
    desc = 'Next usage',
    mode = 'n',
  },
  goto_previous_usage = {
    module = 'nvim-treesitter-locals.navigation',
    fn = 'goto_previous_usage',
    desc = 'Previous usage',
    mode = 'n',
  },
  smart_rename = {
    module = 'nvim-treesitter-locals.rename',
    fn = 'smart_rename',
    desc = 'Smart rename',
    mode = 'n',
  },
  smart_rename_ts = {
    module = 'nvim-treesitter-locals.rename',
    fn = 'smart_rename_ts',
    desc = 'Smart rename (treesitter)',
    mode = 'n',
  },
  goto_implementation = {
    module = 'nvim-treesitter-locals.navigation',
    fn = 'goto_implementation',
    desc = 'Go to implementation',
    mode = 'n',
  },
  find_references_xref = {
    module = 'nvim-treesitter-locals.xref',
    fn = 'find_references',
    desc = 'Find references (cross-file)',
    mode = 'n',
  },
}

--- Get resolved config. Returns defaults if setup() hasn't been called.
---@return NvimTreesitterLocalsOpts
function M.get_config()
  return resolved_config or defaults
end

--- Bind keymaps for a buffer, deferred to run after ftplugin autocmds.
---@param buf integer
---@param keymaps NvimTreesitterLocalsKeymaps
local function bind_keymaps(buf, keymaps)
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    for action, lhs in pairs(keymaps) do
      local spec = keymap_actions[action]
      if lhs and spec then
        vim.keymap.set(spec.mode, lhs, function()
          require(spec.module)[spec.fn](buf)
        end, { buffer = buf, desc = spec.desc })
      end
    end
  end)
end

--- Register user commands for cross-file index management.
local function register_cross_file_commands()
  vim.api.nvim_create_user_command('TSLocalsIndexRebuild', function()
    local buf = vim.api.nvim_get_current_buf()
    local index = require('nvim-treesitter-locals.index')
    local root, lang, file_patterns = index.resolve_xref_config(buf)
    if not root then
      vim.notify('nvim-treesitter-locals: no file patterns for current buffer', vim.log.levels.WARN)
      return
    end
    index.rebuild(root, lang, file_patterns)
    vim.notify('nvim-treesitter-locals: index rebuilt for ' .. root, vim.log.levels.INFO)
  end, { desc = 'Rebuild cross-file symbol index' })

  vim.api.nvim_create_user_command('TSLocalsIndexClear', function()
    require('nvim-treesitter-locals.index').clear()
    vim.notify('nvim-treesitter-locals: index cache cleared', vim.log.levels.INFO)
  end, { desc = 'Clear cross-file symbol index cache' })
end

---@param opts? NvimTreesitterLocalsOpts
function M.setup(opts)
  opts = vim.tbl_deep_extend('force', defaults, opts or {})
  resolved_config = opts

  local keymaps = opts.keymaps or {}
  local has_keymaps = next(keymaps) ~= nil

  if opts.highlight_definitions or has_keymaps then
    vim.api.nvim_create_autocmd('FileType', {
      group = vim.api.nvim_create_augroup('NvimTreesitterLocalsSetup', { clear = true }),
      callback = function(args)
        local buf = args.buf
        if not pcall(vim.treesitter.get_parser, buf) then
          return
        end
        if opts.highlight_definitions then
          require('nvim-treesitter-locals.highlight').enable(buf)
        end
        if has_keymaps then
          bind_keymaps(buf, keymaps)
        end
      end,
    })
  end

  if opts.cross_file then
    register_cross_file_commands()
  end
end

return M
