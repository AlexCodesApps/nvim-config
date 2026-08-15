vim.bo.tabstop = 2
vim.bo.shiftwidth = 2
vim.bo.expandtab = true
-- vim.bo.keywordprg = ':new | term hoogle --info'
vim.bo.makeprg='ghc -fno-code -fforce-recomp -Wincomplete-patterns %'

vim.keymap.set('n', '<M-t>', function()
	local word = vim.fn.expand('<cword>')
	if word == '' then return end
	local repl = require('alex.repl').get_repl_for_buffer(0)
	if not repl then return end
	repl:send_line(':type ' .. word)
end, {})

vim.keymap.set('n', '<M-i>', function()
	local word = vim.fn.expand('<cword>')
	if word == '' then return end
	local repl = require('alex.repl').get_repl_for_buffer(0)
	if not repl then return end
	repl:send_line(':info ' .. word)
end, {})

vim.keymap.set('n', '<M-d>', function()
	local word = vim.fn.expand('<cWORD>')
	if word == '' then return end
	local repl = require('alex.repl').get_repl_for_buffer(0)
	if not repl then return end
	repl:send_line(':doc ' .. word)
end, {})

vim.api.nvim_buf_create_user_command(0, 'CabalEnable', function()
	vim.o.makeprg = 'cabal build'
	vim.bo.makeprg = nil
	local repl = require('alex.repl')
	repl.filetype_repl_table['haskell'].repl = repl.cabal_repl
end, { desc = 'enable cabal project' })
