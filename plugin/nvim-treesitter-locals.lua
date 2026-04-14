if vim.g.loaded_nvim_treesitter_locals then
  return
end
vim.g.loaded_nvim_treesitter_locals = true

-- Default highlight groups
vim.api.nvim_set_hl(0, 'TSDefinition', { default = true, link = 'Search' })
vim.api.nvim_set_hl(0, 'TSDefinitionUsage', { default = true, link = 'CurSearch' })
