-- no thank you
vim.g.loaded_nvim_net_plugin = true

require('alex.remap')
require('alex.pack')
require('alex.remap')
require('alex.lsp')
require('alex.commands')
require('alex.overrides')

vim.o.background = 'dark'
vim.cmd.colorscheme('gruvbox')
vim.g.loaded_perl_provider = 0
vim.g.loaded_node_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_python3_provider = 0
if vim.g.neovide then
	vim.g.neovide_cursor_animation_length = 0
	vim.g.neovide_scroll_animation_length = 0
	vim.g.neovide_scale_factor = 0.66
	vim.g.neovide_position_animation_length = 0
	vim.g.neovide_cursor_animate_command_line = false
end

vim.o.pumborder = 'rounded'
vim.o.winborder = 'rounded'
vim.o.pumblend = 5
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
vim.g.netrw_altfile = 1
vim.g.ffind_gitignore = 1
vim.o.completeopt = 'menuone,noinsert,fuzzy'
vim.o.wildoptions = 'pum,tagfile,fuzzy'
vim.o.wildmode = 'list:longest,full'
vim.o.showtabline = 1
vim.o.shortmess = vim.o.shortmess .. 'I'

do
	local ok, devicons = pcall(require, 'nvim-web-devicons')
	if ok then
		function _G.StatusLineIcon()
			if vim.api.nvim_get_current_win() ~= tonumber(vim.g.actual_curwin) then
				return ''
			end
			local icon, hl = devicons.get_icon_by_filetype(vim.bo.filetype, { default = true })
			return table.concat {
				'%#', hl, '#',
				icon,
				'%*',
				'  '
			}
		end
		local statusline = vim.o.statusline
		statusline = '%{%v:lua.StatusLineIcon()%}' .. statusline
		vim.o.statusline = statusline
	end
end

vim.cmd.packadd('cfilter')

require('alex.cswitch').add_extension_pairs({
	{ 'c', 'h', },
	{ 'cc', 'hh' },
	{ 'cpp', 'hpp' },
	{ 'js', 'html' },
	{ 'ts', 'html' },
})

vim.api.nvim_create_autocmd('TextYankPost', {
	callback = function()
		vim.hl.on_yank {
			timeout = 100
		}
	end
})

require('alex.projconf')
