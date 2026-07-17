return {
	'stevearc/oil.nvim',
	dependencies = {
		'nvim-tree/nvim-web-devicons'
	},
	config = function()
		require('oil').setup {
			buf_options = {
				bufhidden = 'wipe',
			},
			view_options = {
				show_hidden = true
			}
		}
		local config_path = vim.fn.stdpath('config')
		vim.keymap.set('n', '<leader>ee', ':keepjumps Oil<CR>')
		vim.keymap.set('n', '<leader>ec', ':keepjumps Oil ' .. config_path .. '<CR>')
	end
}
