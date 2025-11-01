local api = require('alex.api')

vim.api.nvim_create_autocmd('BufLeave', {
	callback = function(ev)
		if vim.bo[ev.buf].buftype == 'quickfix' then
			vim.api.nvim_buf_delete(ev.buf, {})
		end
	end
})

vim.api.nvim_create_autocmd('BufEnter', {
	pattern = api.home_dir() .. '/Documents/**/*.md',
	callback = function(_)
		if vim.bo.filetype == 'markdown' then
			vim.opt_local.spell = true
			vim.opt_local.wrap = true
			vim.opt_local.relativenumber = false
			vim.keymap.set('n', 'j', 'gj', { buffer = true })
			vim.keymap.set('n', 'k', 'gk', { buffer = true })
		end
	end
})
