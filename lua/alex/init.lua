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
vim.g.signcolumn = "yes:1"
vim.g.netrw_banner = 0
vim.o.completeopt = "menuone,noinsert,fuzzy"
vim.o.indentexpr = "nvim_treesitter#indent()"
vim.o.showtabline = 0

-- local blink = require('blink.cmp')
-- local function split_signature()
-- 	if not blink.show_documentation() then
-- 		vim.print("couldn't show signature")
-- 		return
-- 	end
-- 	local text = vim.api.nvim_buf_get_lines(0, 0, -1, false)
-- 	if text == "" then
-- 		return
-- 	end
-- 	local bufid = vim.api.nvim_create_buf(false, true)
-- 	if bufid == 0 then
-- 		return
-- 	end
-- 	vim.api.nvim_buf_set_lines(bufid, 0, -1, false, text)
-- 	vim.cmd('vsplit')
-- 	vim.api.nvim_set_current_buf(bufid)
-- end
-- vim.keymap.set('n', '<leader>d', split_signature)
