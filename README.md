# nvim-treesitter-locals

LSP-like functionality (rename, goto definition, references, highlight definitions) powered by Treesitter.

This project is a rewrite of [nvim-treesitter-refactor](https://github.com/nvim-treesitter/nvim-treesitter-refactor) which is no longer compatible with nvim-treesitter on the main branch.
There is no dependencies as it relies on Neovim's built-in treesitter support.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "PlatyPew/nvim-treesitter-locals",
  opts = {
    highlight_definitions = true,
    keymaps = {
      smart_rename = "gnr",
      goto_definition = "gnd",
      goto_next_usage = "]]",
      goto_previous_usage = "[[",
    },
  },
}
```

## Setup Options

| Option                  | Type    | Default | Description                                     |
| ----------------------- | ------- | ------- | ----------------------------------------------- |
| `highlight_definitions` | boolean | `false` | Auto-highlight definitions/usages on CursorHold |
| `keymaps`               | table   | `{}`    | Keybinding table (see below)                    |

### Available Keymaps

| Key                   | Description                                  |
| --------------------- | -------------------------------------------- |
| `goto_definition`     | Go to definition (LSP → treesitter fallback) |
| `goto_definition_ts`  | Go to definition (treesitter only)           |
| `goto_next_usage`     | Next usage (wraps around)                    |
| `goto_previous_usage` | Previous usage (wraps around)                |
| `smart_rename`        | Rename symbol (LSP → treesitter fallback)    |
| `smart_rename_ts`     | Rename symbol (treesitter only)              |

## Features

All features are also available as plain Lua functions you can call directly, without using `setup()`.

Functions with LSP equivalents (`goto_definition`, `smart_rename`) automatically use LSP when a capable server is attached, falling back to treesitter. `_ts()` variants are available to bypass LSP.

### Highlight Definitions

Highlights the definition and all usages of the symbol under the cursor on `CursorHold`. When using `setup()`, set `highlight_definitions = true`. Otherwise, enable manually per buffer:

```lua
require('nvim-treesitter-locals.highlight').enable(bufnr)
```

| Function                                  | Description                        |
| ----------------------------------------- | ---------------------------------- |
| `highlight.enable(bufnr?)`                | Enable auto-highlight for a buffer |
| `highlight.disable(bufnr?)`               | Disable and clear highlights       |
| `highlight.toggle(bufnr?)`                | Toggle on/off                      |
| `highlight.highlight_definitions(bufnr?)` | Manually trigger once              |
| `highlight.clear_highlights(bufnr?)`      | Manually clear                     |

### Navigation

| Function                                 | Description                                  |
| ---------------------------------------- | -------------------------------------------- |
| `navigation.goto_definition(bufnr?)`     | Go to definition (LSP → treesitter fallback) |
| `navigation.goto_definition_ts(bufnr?)`  | Go to definition (treesitter only)           |
| `navigation.goto_next_usage(bufnr?)`     | Next usage (wraps around)                    |
| `navigation.goto_previous_usage(bufnr?)` | Previous usage (wraps around)                |

### Smart Rename

| Function                         | Description                               |
| -------------------------------- | ----------------------------------------- |
| `rename.smart_rename(bufnr?)`    | Rename symbol (LSP → treesitter fallback) |
| `rename.smart_rename_ts(bufnr?)` | Rename symbol (treesitter only)           |

## Highlight Groups

| Group               | Default     | Description         |
| ------------------- | ----------- | ------------------- |
| `TSDefinition`      | `Search`    | The definition node |
| `TSDefinitionUsage` | `CurSearch` | Usage nodes         |

## Misc

Did I vibe-code this? Yes, I did.
Am I proud of it? No, I'm not.
I'm so sorry but I just needed this plugin so badly I had to vibe-code it myself.
Sorry to all software developers out there, I have failed you.
