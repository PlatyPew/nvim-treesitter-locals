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
---@field goto_implementation? string|false Go to implementation (all definitions across project)
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
        local ok = pcall(vim.treesitter.get_parser, buf)
        if not ok then
          return
        end

        if opts.highlight_definitions then
          require('nvim-treesitter-locals.highlight').enable(buf)
        end

        if has_keymaps then
          -- Defer to run after ftplugin autocmds, which fixes ]] / [[ overrides
          -- in languages like Python whose ftplugin sets buffer-local mappings
          vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(buf) then
              return
            end
            for action, lhs in pairs(keymaps) do
              if lhs and keymap_actions[action] then
                local spec = keymap_actions[action]
                vim.keymap.set(spec.mode, lhs, function()
                  require(spec.module)[spec.fn](buf)
                end, { buffer = buf, desc = spec.desc })
              end
            end
          end)
        end
      end,
    })
  end

  -- Cross-file index commands (only when cross_file enabled)
  if opts.cross_file then
    vim.api.nvim_create_user_command('TSLocalsIndexRebuild', function()
      local buf = vim.api.nvim_get_current_buf()
      local cf = type(opts.cross_file) == 'table' and opts.cross_file or {}
      local ft = vim.bo[buf].filetype
      local lang = cf.lang or vim.treesitter.language.get_lang(ft) or ft
      local index = require('nvim-treesitter-locals.index')
      local file_patterns = cf.file_patterns or index.lang_patterns[lang]
      if not file_patterns then
        vim.notify('nvim-treesitter-locals: no file patterns for language: ' .. lang, vim.log.levels.WARN)
        return
      end
      local root = require('nvim-treesitter-locals.project').find_root(buf, cf.root_markers)
      index.rebuild(root, lang, file_patterns)
      vim.notify('nvim-treesitter-locals: index rebuilt for ' .. root, vim.log.levels.INFO)
    end, { desc = 'Rebuild cross-file symbol index' })

    vim.api.nvim_create_user_command('TSLocalsIndexClear', function()
      require('nvim-treesitter-locals.index').clear()
      vim.notify('nvim-treesitter-locals: index cache cleared', vim.log.levels.INFO)
    end, { desc = 'Clear cross-file symbol index cache' })
  end
end

return M
