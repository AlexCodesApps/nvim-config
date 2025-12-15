local config_path = vim.fn.stdpath('config')
local api = require('alex.api')
vim.g.mapleader = ' '
vim.keymap.set('n', '<leader>ee', ':Ex<CR>')
vim.keymap.set('n', '<leader>ec', ':Ex ' .. config_path .. '<CR>')
vim.keymap.set('n', '<leader>;', [[mpA;<Esc>`p]])
vim.keymap.set('n', '<leader>,', [[mpA,<Esc>`p]])
vim.keymap.set('n', '<leader>.', [[mpA.<Esc>`p]])
vim.keymap.set('n', '<C-h>', '<C-w><C-h>')
vim.keymap.set('n', '<C-j>', '<C-w><C-j>')
vim.keymap.set('n', '<C-k>', '<C-w><C-k>')
vim.keymap.set('n', '<C-l>', '<C-w><C-l>')
vim.keymap.set({'n', 'x'}, '<leader>y', '"+y')
vim.keymap.set({'n', 'x'}, '<leader>p', '"+p')
vim.keymap.set({'n', 'x'}, '<leader>P', '"+P')
vim.keymap.set({'n', 'x'}, '<S-Tab>', function()
	if vim.w.focused_window then
		local winid = vim.w.focused_window
		local pos = vim.api.nvim_win_get_cursor(0)
		local bufid = vim.api.nvim_get_current_buf()
		vim.cmd.tabclose()
		vim.api.nvim_set_current_win(winid)
		vim.api.nvim_set_current_buf(bufid)
		vim.api.nvim_win_set_cursor(0, pos)
		return
	end
	local winid = vim.api.nvim_get_current_win()
	local st = vim.wo.statusline
	if st == '' then st = '%F' end
	vim.cmd('tab split')
	vim.wo.statusline = st .. ' (ZOOMED)'
	vim.w.focused_window = winid
end)

for i=0,9 do
	vim.keymap.set('n', ('<M-%d>'):format(i), ('%dgt'):format(i))
end

vim.keymap.set({'n'}, '<leader>t', function()
	local function on_input(input)
		if not input or input == '' then return end
		local output = ('<%s></%s>'):format(input, input)
		vim.api.nvim_paste(output, false, -1)
		vim.cmd('norm ' .. tostring(#input + 3) .. 'h')
	end
	vim.ui.input({
		prompt = 'Enter the HTML tag: ',
	}, on_input)
end)

vim.keymap.set('i', '<C-t>', function()
	local function on_input(input)
		if not input or input == '' then return end
		local output = ('<%s></%s>'):format(input, input)
		vim.api.nvim_paste(output, false, -1)
		vim.cmd('norm ' .. tostring(#input + 3) .. 'h')
	end
	vim.ui.input({
		prompt = 'Enter the HTML tag: ',
	}, on_input)
end)

local ffind = require('alex.ffind')
vim.keymap.set('n', '<leader>ff', function()
	ffind.find_file {
		exclude_pattern = vim.g.ffind_exclude_pattern,
		gitignore = vim.g.ffind_gitignore == 1,
	}
end)
vim.keymap.set('n', '<leader>fc', function()
	ffind.find_file {
		cwd = vim.fn.stdpath('config'),
		gitignore = true,
	}
end)
vim.keymap.set('n', '<leader>fr', function()
	ffind.find_file {
		cwd = api.home_dir(),
		gitignore = false,
	}
end)
vim.keymap.set('n', '<leader>fg', function()
	ffind.grep_files {
		exclude_pattern = vim.g.ffind_exclude_pattern,
		gitignore = vim.g.ffind_gitignore == 1
	}
end)
vim.keymap.set('n', '<leader>fh', ffind.find_help)
vim.keymap.set('n', '<leader>fo', ffind.document_symbols)
vim.keymap.set('n', '<leader>fw', ffind.workspace_symbols)
vim.keymap.set('n', '<leader>fm', ffind.find_manpage)
vim.keymap.set('n', '<leader>fb', ffind.find_buffer)
vim.keymap.set('n', '<leader>ft', ffind.find_colorscheme)

vim.keymap.set('n', '<leader>de', function()
	vim.diagnostic.setqflist {
		severity = 'ERROR',
	}
end)
vim.keymap.set('n', '<leader>dw', function()
	vim.diagnostic.setqflist {
		severity = 'WARN',
	}
end)
vim.keymap.set('n', '<leader>da', vim.diagnostic.setqflist)
