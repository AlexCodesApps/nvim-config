vim.bo.tabstop = 2
vim.bo.shiftwidth = 2
vim.bo.expandtab = true
vim.bo.keywordprg = ':new | term hoogle --info'
-- vim.bo.makeprg="cabal build"
vim.bo.makeprg='ghc -fno-code -fforce-recomp -Wincomplete-patterns %'

vim.keymap.set('n', '<M-t>', function()
	local word = vim.fn.expand('<cword>')
	if word == '' then return end
	local repl = require('alex.repl').buffer_repl(0)
	if not repl then return end
	repl:send_oneline_input(':type ' .. word)
end, {})

vim.keymap.set('n', '<M-i>', function()
	local word = vim.fn.expand('<cword>')
	if word == '' then return end
	local repl = require('alex.repl').buffer_repl(0)
	if not repl then return end
	repl:send_oneline_input(':info ' .. word)
end, {})

vim.keymap.set('n', '<M-d>', function()
	local word = vim.fn.expand('<cWORD>')
	if word == '' then return end
	local repl = require('alex.repl').buffer_repl(0)
	if not repl then return end
	repl:send_oneline_input(':doc ' .. word)
end, {})

vim.api.nvim_buf_create_user_command(0, 'CabalEnable', function()
	vim.o.makeprg = 'cabal build'
	vim.bo.makeprg = nil
	local arepl = require('alex.repl')
	arepl.filetype_repl_table['haskell'].repl = arepl.cabal_repl
end, { desc = 'enable cabal project' })
