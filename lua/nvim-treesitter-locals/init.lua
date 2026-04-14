local M = {}

---@class NvimTreesitterLocalsOpts
---@field highlight_definitions? boolean Enable auto-highlight on CursorHold for all treesitter buffers (default: false)
---@field keymaps? NvimTreesitterLocalsKeymaps Keybindings (set to false to disable a default, or string to override)

---@class NvimTreesitterLocalsKeymaps
---@field goto_definition? string|false Go to definition (LSP -> treesitter fallback)
---@field goto_definition_ts? string|false Go to definition (treesitter only)
---@field goto_next_usage? string|false Next usage (wraps around)
---@field goto_previous_usage? string|false Previous usage (wraps around)
---@field smart_rename? string|false Rename symbol (LSP -> treesitter fallback)
---@field smart_rename_ts? string|false Rename symbol (treesitter only)

---@type NvimTreesitterLocalsOpts
local defaults = {
  highlight_definitions = false,
  keymaps = {},
}

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
}

---@param opts? NvimTreesitterLocalsOpts
function M.setup(opts)
  opts = vim.tbl_deep_extend('force', defaults, opts or {})

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
end

return M
