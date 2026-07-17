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
vim.keymap.set('c', '<C-a>', '<Home>')
vim.keymap.set('c', '<C-e>', '<End>')
vim.keymap.set('n', '<leader>s', ':%y +<CR>')
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

---@param input string
---@return string
local function format_html_tag(input)
	local self_closing = {
		area = true,
		base = true,
		br = true,
		col = true,
		embed = true,
		hr = true,
		img = true,
		input = true,
		link = true,
		meta = true,
		param = true,
		source = true,
		track = true,
		wbr = true,
		command = true,
		keygen = true,
		menuitem = true,
		frame = true,
	}
	if self_closing[input] then
		return ('<%s>'):format(input)
	end
	return ('<%s></%s>'):format(input, input)
end

local function insert_html_tag()
	local function on_input(input)
		if not input or input == '' then return end
		local output = format_html_tag(input)
		vim.api.nvim_paste(output, false, -1)
		vim.cmd('norm ' .. tostring(#input + 3) .. 'h')
	end
	vim.ui.input({
		prompt = 'Enter the HTML tag: ',
	}, on_input)
end

vim.keymap.set('n', '<leader>t', insert_html_tag)

vim.keymap.set('i', '<C-t>', insert_html_tag)

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
		severity = vim.diagnostic.severity.ERROR,
	}
end)
vim.keymap.set('n', '<leader>dw', function()
	vim.diagnostic.setqflist {
		severity = vim.diagnostic.severity.WARN,
	}
end)
vim.keymap.set('n', '<leader>da', vim.diagnostic.setqflist)

vim.keymap.set('n', '<leader>fdr', function()
	local rustdoc = require('alex.rustdoc')
	local syms = rustdoc.get_docs()
	if not syms then return end
	local entries = vim.tbl_map(function(sym)
		return ffind.picker_entry.new(string.format('[%s] %s', sym.category, sym.name), sym)
	end, syms)
	ffind.open_picker(entries, {
		actions = {
			on_select = function(entry, _)
				rustdoc.open_file(entry.data.file)
			end
		}
	})
end)
