# nvim-treesitter-locals

LSP-like functionality (rename, goto definition, references, selection range) based on [treesitter locals](https://github.com/nvim-treesitter/nvim-treesitter/blob/main/CONTRIBUTING.md#locals)

> [!WARNING]
> Nothing to see here yet.

### Roadmap

* [ ] rename
* [ ] goto definition
* [ ] references
* [ ] document highlight
* [ ] selection range (the function formerly known as highlight scope/incremental selection)

### Design constraints:
* no setup
* expose single function per feature to be mapped by users
* provide "smart" mappings (check for attached LSP client with capability, then for parser and query) as `<Plug>` mapping.
* user commands?
* use Nvim core API (`vim.pos`, `vim.range`), not nvim-treesitter
