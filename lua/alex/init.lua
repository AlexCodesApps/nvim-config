require('alex.remap')
require('alex.lazy')
require('alex.lsp')
require('alex.commands')
require('alex.floaterm')
require('alex.autocmd')
require('alex.overrides')

vim.o.background = 'dark'
vim.cmd.colorscheme('github_dark_default')
vim.g.loaded_perl_provider = 0
vim.g.loaded_node_provider = 0
vim.g.loaded_ruby_provider = 0
if vim.g.neovide then
	vim.g.neovide_cursor_animation_length = 0
	vim.g.neovide_scroll_animation_length = 0
	vim.g.neovide_scale_factor = 0.66
	vim.g.neovide_position_animation_length = 0
	vim.g.neovide_cursor_animate_command_line = false
end

vim.o.splitright = true
vim.o.tabstop = 4
vim.o.shiftwidth = 4
vim.o.number = true
vim.o.relativenumber = true
vim.o.list = true
vim.o.mouse = ''
vim.o.wrap = false
vim.o.linebreak = true
vim.o.scrolloff = 4
vim.o.hls = false
vim.g.c_no_curly_error = 1
vim.g.signcolumn = 'yes:1'
vim.g.netrw_banner = 0
vim.g.ffind_gitignore = 1
vim.o.completeopt = 'menuone,noinsert,fuzzy'
vim.o.indentexpr = 'nvim_treesitter#indent()'
vim.o.showtabline = 0
vim.o.shortmess = vim.o.shortmess .. 'I'

require('alex.projconf')
