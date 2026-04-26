# nvim-treesitter-locals

LSP-like functionality (rename, goto definition, references, highlight definitions) powered by Treesitter.

This project is a rewrite of [nvim-treesitter-refactor](https://github.com/nvim-treesitter/nvim-treesitter-refactor) which is no longer compatible with nvim-treesitter on the main branch.
There are no dependencies for local buffer features as it relies on Neovim's built-in treesitter support. Cross-file features require [snacks.nvim](https://github.com/folke/snacks.nvim) for the picker UI.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "PlatyPew/nvim-treesitter-locals",
  depends = "folke/snacks.nvim",
  opts = {
    highlight_definitions = true,
    keymaps = {
      smart_rename = "gnr",
      goto_next_usage = "]]",
      goto_previous_usage = "[[",
      goto_implementation = "gni",
      goto_definition = "gnd",
    },
    cross_file = true,
  },
}
```

## Setup Options

| Option                  | Type           | Default | Description                                             |
| ----------------------- | -------------- | ------- | ------------------------------------------------------- |
| `highlight_definitions` | boolean        | `false` | Auto-highlight definitions/usages on CursorHold         |
| `keymaps`               | table          | `{}`    | Keybinding table (see below)                            |
| `cross_file`            | boolean\|table | `false` | Enable cross-file features. Set `true` for auto-detect. |

### Available Keymaps

| Key                    | Description                                       |
| ---------------------- | ------------------------------------------------- |
| `goto_definition`      | Go to definition (LSP → treesitter fallback)      |
| `goto_definition_ts`   | Go to definition (treesitter only)                |
| `goto_next_usage`      | Next usage (wraps around)                         |
| `goto_previous_usage`  | Previous usage (wraps around)                     |
| `smart_rename`         | Rename symbol (LSP → treesitter fallback)         |
| `smart_rename_ts`      | Rename symbol (treesitter only)                   |
| `goto_implementation`  | All usages across project (requires `cross_file`) |
| `find_references_xref` | Cross-file references (requires `cross_file`)     |

### Cross-File Options

When `cross_file` is set to `true`, file patterns are auto-detected from the buffer's language. You can override specific settings by passing a table instead:

```lua
cross_file = {
  root_markers = { ".git", "Makefile", "compile_commands.json" }, -- default
  file_patterns = { "*.c", "*.h" },  -- override auto-detect
  lang = "c",                         -- override auto-detect
}
```

Auto-detected languages: C, C++, Python, JavaScript, TypeScript, Lua, Rust, Go, Java, Zig.

## Features

All features are also available as plain Lua functions you can call directly, without using `setup()`.

Functions with LSP equivalents (`goto_definition`, `smart_rename`) automatically use LSP when a capable server is attached, falling back to treesitter. `_ts` variants are available to bypass LSP.

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

| Function                                 | Description                                       |
| ---------------------------------------- | ------------------------------------------------- |
| `navigation.goto_definition(bufnr?)`     | Go to definition (LSP → treesitter fallback)      |
| `navigation.goto_definition_ts(bufnr?)`  | Go to definition (treesitter only)                |
| `navigation.goto_next_usage(bufnr?)`     | Next usage (wraps around)                         |
| `navigation.goto_previous_usage(bufnr?)` | Previous usage (wraps around)                     |
| `navigation.goto_implementation(bufnr?)` | All usages across project (requires `cross_file`) |

When `cross_file` is enabled, `goto_definition` shows results in a picker (local + external definitions). `goto_implementation` collects all usages of the symbol across the project, excluding the definition itself.

### Cross-File References

Requires `cross_file` enabled and [snacks.nvim](https://github.com/folke/snacks.nvim) for the picker.

| Function                       | Description                                         |
| ------------------------------ | --------------------------------------------------- |
| `xref.find_references(bufnr?)` | Find all cross-file references for symbol at cursor |

Uses ripgrep to narrow candidates, then treesitter to parse and verify matches.

### Smart Rename

| Function                         | Description                               |
| -------------------------------- | ----------------------------------------- |
| `rename.smart_rename(bufnr?)`    | Rename symbol (LSP → treesitter fallback) |
| `rename.smart_rename_ts(bufnr?)` | Rename symbol (treesitter only)           |

## Commands

Available when `cross_file` is enabled:

| Command                 | Description                         |
| ----------------------- | ----------------------------------- |
| `:TSLocalsIndexRebuild` | Rebuild cross-file symbol index     |
| `:TSLocalsIndexClear`   | Clear cross-file symbol index cache |

The symbol index is built lazily on first use, cached in memory, and persisted to disk (`stdpath('cache')/nvim-treesitter-locals/`). It updates incrementally by checking file modification times.

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
