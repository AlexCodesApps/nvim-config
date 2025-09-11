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

---@diagnostic disable-next-line: unused-local, duplicate-set-field
vim.notify = function(msg, level, opts)
	local _ = opts
	vim.system({
		'hyprctl',
		'notify',
		'0',
		'3000',
		'rgb(FFFF00)',
		msg
	})
end
