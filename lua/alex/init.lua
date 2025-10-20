require('alex.remap')
require('alex.lazy')
require('alex.lsp')
require('alex.floaterm').setup()
local api = require('alex.api')
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
vim.o.mouse = ""
vim.o.wrap = false
vim.o.linebreak = true
vim.o.scrolloff = 4
vim.o.hls = false
vim.g.c_no_curly_error = 1
vim.g.signcolumn = 'yes:1'
vim.g.netrw_banner = 0
vim.g.ffind_gitignore = 1
vim.o.completeopt = "menuone,noinsert,fuzzy"
vim.o.indentexpr = "nvim_treesitter#indent()"
vim.o.showtabline = 0
vim.o.shortmess = vim.o.shortmess .. "I"
vim.api.nvim_create_autocmd('BufLeave', {
	callback = function(ev)
		if vim.bo[ev.buf].buftype == 'quickfix' then
			vim.api.nvim_buf_delete(ev.buf, {})
		end
	end
})
vim.api.nvim_create_autocmd('BufEnter', {
	pattern = api.home_dir() .. "/Documents/**/*.md",
	callback = function(_)
		if vim.bo.filetype == 'markdown' then
			vim.opt_local.spell = true
			vim.opt_local.wrap = true
			vim.opt_local.relativenumber = false
			vim.keymap.set("n", "j", "gj", { buffer = true })
			vim.keymap.set("n", "k", "gk", { buffer = true })
		end
	end
})

if 1 == vim.fn.executable 'hyprctl' then
	---@diagnostic disable-next-line: duplicate-set-field
	vim.notify = function(msg, level, _)
		level = level or vim.log.levels.OFF
		local table = {
			[vim.log.levels.WARN] = { icon = '0', color = 'rgb(FFFF00)' },
			[vim.log.levels.ERROR] = { icon = '3', color = 'rbg(FF0000)' },
		}
		local info = table[level] or {}
		local icon = info.icon or '1'
		local color = info.color or "rbg(0000FF)"
		vim.system {
			'hyprctl',
			'notify',
			icon,
			'3000',
			color,
			msg
		}
	end
end

require("alex.projconf").setup()
