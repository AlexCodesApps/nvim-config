require('alex.lazy')
require('alex.lsp')
require('alex.floaterm').setup()
vim.cmd.colorscheme('github_dark_default')
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
vim.api.nvim_create_autocmd('BufLeave', {
	callback = function(ev)
		if vim.bo[ev.buf].buftype == 'quickfix' then
			vim.api.nvim_buf_delete(ev.buf, {})
		end
	end
})

if 1 == vim.fn.executable "hyprctl" then
	---@diagnostic disable-next-line: unused-local, duplicate-set-field
	vim.notify = function(msg, level, opts)
		level = level or vim.log.levels.OFF
		local table = {
			[vim.log.levels.WARN] = { icon = '0', color = 'rgb(FFFF00)' },
			[vim.log.levels.ERROR] = { icon = '3', color = 'rbg(FF0000)' },
		}
		local info = table[level] or {}
		local icon = info.icon or '1'
		local color = info.color or "rbg(0000FF)"
		local _ = opts
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
