# nvim-treesitter-locals

Did I vibe-code this? Yes, I did.
Am I proud of it? No, I'm not.
I'm so sorry but I just needed this plugin so badly I had to vibe-code it myself.
Sorry to all software developers out there, I have failed you.

LSP-like functionality (rename, goto definition, references, highlight definitions) powered by [treesitter locals](https://github.com/nvim-treesitter/nvim-treesitter/blob/main/CONTRIBUTING.md#locals) — no LSP required.

## Requirements

- Neovim >= 0.10
- `locals.scm` query files for your language(s) (Neovim ships some built-in; for others, install from [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter))

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'nvim-treesitter/nvim-treesitter-locals',
}
```

## Features

No setup function required. No default keybinds. All features are plain Lua functions you call directly.

Functions with LSP equivalents (`goto_definition`, `smart_rename`) automatically use LSP when a capable server is attached, falling back to treesitter. `_ts()` variants are available to bypass LSP.

### Highlight Definitions

Highlights the definition and all usages of the symbol under the cursor on `CursorHold`. Opt-in per buffer.

```lua
-- Enable for all buffers with a treesitter parser
vim.api.nvim_create_autocmd('FileType', {
  callback = function(args)
    local ok = pcall(vim.treesitter.get_parser, args.buf)
    if ok then
      require('nvim-treesitter-locals.highlight').enable(args.buf)
    end
  end,
})
```

| Function                                  | Description                        |
| ----------------------------------------- | ---------------------------------- |
| `highlight.enable(bufnr?)`                | Enable auto-highlight for a buffer |
| `highlight.disable(bufnr?)`               | Disable and clear highlights       |
| `highlight.toggle(bufnr?)`                | Toggle on/off                      |
| `highlight.highlight_definitions(bufnr?)` | Manually trigger once              |
| `highlight.clear_highlights(bufnr?)`      | Manually clear                     |

### Navigation

```lua
local nav = require('nvim-treesitter-locals.navigation')
vim.keymap.set('n', 'gd', nav.goto_definition, { desc = 'Go to definition' })
vim.keymap.set('n', '<a-*>', nav.goto_next_usage, { desc = 'Next usage' })
vim.keymap.set('n', '<a-#>', nav.goto_previous_usage, { desc = 'Previous usage' })
```

| Function                                 | Description                                  |
| ---------------------------------------- | -------------------------------------------- |
| `navigation.goto_definition(bufnr?)`     | Go to definition (LSP → treesitter fallback) |
| `navigation.goto_definition_ts(bufnr?)`  | Go to definition (treesitter only)           |
| `navigation.goto_next_usage(bufnr?)`     | Next usage (wraps around)                    |
| `navigation.goto_previous_usage(bufnr?)` | Previous usage (wraps around)                |

### Smart Rename

```lua
local rename = require('nvim-treesitter-locals.rename')
vim.keymap.set('n', '<leader>rn', rename.smart_rename, { desc = 'Smart rename' })
```

| Function                         | Description                               |
| -------------------------------- | ----------------------------------------- |
| `rename.smart_rename(bufnr?)`    | Rename symbol (LSP → treesitter fallback) |
| `rename.smart_rename_ts(bufnr?)` | Rename symbol (treesitter only)           |

## Highlight Groups

| Group               | Default     | Description         |
| ------------------- | ----------- | ------------------- |
| `TSDefinition`      | `Search`    | The definition node |
| `TSDefinitionUsage` | `CurSearch` | Usage nodes         |

## Design

- Zero dependencies — uses only Neovim built-in treesitter APIs
- No setup function required
- No default keybinds
- Single function per feature
