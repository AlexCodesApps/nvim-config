local path = vim.fn.stdpath('config')
vim.g.mapleader = ' '
vim.keymap.set('n', '<leader>ee', ':Ex<CR>')
vim.keymap.set('n', '<leader>ec', ':Ex ' .. path .. '<CR>')
vim.keymap.set('n', '<leader>;', [[mpA;<Esc>`p]])
vim.keymap.set('n', '<leader>,', [[mpA,<Esc>`p]])
vim.keymap.set('n', '<C-h>', '<C-w><C-h>')
vim.keymap.set('n', '<C-j>', '<C-w><C-j>')
vim.keymap.set('n', '<C-k>', '<C-w><C-k>')
vim.keymap.set('n', '<C-l>', '<C-w><C-l>')
vim.keymap.set('n', '<leader>bn', ':bnext<CR>')
vim.keymap.set('n', '<leader>bp', ':bprev<CR>')
vim.keymap.set('n', '<leader>n', 'o<Esc>k')
vim.keymap.set('n', '<leader>N', 'O<Esc>j')
vim.keymap.set({'n', 'x'}, '<leader>y', '"+y')
vim.keymap.set({'n', 'x'}, '<leader>p', '"+p')
vim.keymap.set({'n', 'x'}, '<leader>P', '"+P')
vim.keymap.set({'n', 't'}, '<C-x>z', require('alex.floaterm').toggle)
vim.keymap.set({'n', 't'}, '<C-x><C-z>', require('alex.floaterm').toggle)
vim.keymap.set({'n', 'x'}, '<S-Tab>', function()
	if vim.w.alex_focus then
		local state = vim.w.alex_focus
		local pos = vim.api.nvim_win_get_cursor(0)
		local bufid = vim.api.nvim_get_current_buf()
		vim.cmd.tabclose()
		vim.api.nvim_set_current_tabpage(state.tabid)
		vim.api.nvim_set_current_win(state.winid)
		vim.api.nvim_set_current_buf(bufid)
		vim.api.nvim_win_set_cursor(0, pos)
		return
	end
	local bufid = vim.api.nvim_get_current_buf()
	local winid = vim.api.nvim_get_current_win()
	local tabid = vim.api.nvim_get_current_tabpage()
	local pos = vim.api.nvim_win_get_cursor(0)
	vim.cmd.tabnew()
	vim.api.nvim_set_current_buf(bufid)
	vim.api.nvim_win_set_cursor(0, pos)
	vim.w.alex_focus = {
		winid = winid,
		tabid = tabid,
	}
end)
