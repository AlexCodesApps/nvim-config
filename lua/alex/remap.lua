local config_path = vim.fn.stdpath('config')
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

vim.keymap.set('n', '<leader>ff', function()
	require('alex.ffind').find_file {
		exclude_pattern = vim.g.ffind_exclude_pattern,
		gitignore = vim.g.ffind_gitignore == 1,
	}
end)
vim.keymap.set('n', '<leader>fc', function()
	require('alex.ffind').find_file {
		cwd = vim.fn.stdpath('config'),
		gitignore = true,
	}
end)
local ffind = require('alex.ffind')
vim.keymap.set('n', '<leader>fr', function()
	ffind.find_file {
		cwd = os.getenv('HOME'),
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
		severity = "ERROR",
	}
end)
vim.keymap.set('n', '<leader>dw', function()
	vim.diagnostic.setqflist {
		severity = "WARN",
	}
end)
vim.keymap.set('n', '<leader>da', vim.diagnostic.setqflist)
vim.api.nvim_create_user_command("CSwitch", function()
	local path = vim.api.nvim_buf_get_name(0)
	local filename, extension = path:match([[/([^/]+)%.(%a+)$]])
	if not filename then return end
	local ext_table = {
		["c"] = "h",
		["h"] = "c",
		["cpp"] = "hpp",
		["hpp"] = "cpp",
	}
	local extension2 = ext_table[extension]
	if extension2 == nil then return end
	local files = vim.fn.findfile(filename .. "." .. extension2, "**/*", -1)
	if #files ~= 1 then return end
	vim.cmd("e " .. vim.fn.fnameescape(files[1]))
end, {})

vim.api.nvim_create_user_command("MkMdTable", function(opts)
	local input = vim.api.nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, true)
	if #input < 2 then return end
	local header = input[1]
	table.remove(input, 1)
	local header_list = vim.split(header, "|")
	local width = #header_list
	if width < 1 then return end
	local tbl = {}
	local padtbl = vim.tbl_map(string.len, header_list)
	for i=1, #input do
		local line = input[i]
		local items = vim.split(line, "|")
		if #items ~= width then
			vim.notify("Width of table is not regular!")
			return
		end
		for j=1,width do
			padtbl[j] =
				math.max(padtbl[j], items[j]:len())
		end
		tbl[i] = items
	end
	local function print_row(row)
		local o = ""
		for i=1, #row do
			local str = row[i]
			local mwidth = padtbl[i]
			local pad = mwidth - str:len() + 1
			for _=1,pad do
				str = str .. " "
			end
			o = o .. "| " .. str
		end
		o = o .. "|"
		return o
	end
	local output = {
		print_row(header_list)
	}
	local sep = "|"
	for _, itemw in ipairs(padtbl) do
		sep = sep .. "-"
		for _=1,itemw do
			sep = sep .. "-"
		end
		sep = sep .. "-|"
	end
	table.insert(output, sep)
	for _, row in ipairs(tbl) do
		table.insert(output, print_row(row))
	end
	vim.api.nvim_buf_set_lines(0, opts.line1 - 1, opts.line2, true, output)
end, { desc = "Make markdown table", range = true })

vim.api.nvim_create_user_command("UnMkMdTable", function(opts)
	local input = vim.api.nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, true)
	if #input < 3 then return end
	table.remove(input, 2)
	local output = {}
	for _, line in ipairs(input) do
		local output_line = line
			:gsub("%s*|%s*", "|")
			:match("^|(.*)|$")
		if not output_line then
			vim.notify("Invalid syntax")
			return
		end
		table.insert(output, output_line)
	end
	vim.api.nvim_buf_set_lines(0, opts.line1 - 1, opts.line2, true, output)
end, { desc = "Unmake markdown table", range = true })

vim.api.nvim_create_user_command("Pad", function(tbl)
	local count = tonumber(tbl.args)
	local fmt = [[s/.*/\=printf('%-]] .. count .. [[s', submatch(0))]]
	local cmd = vim.api.nvim_parse_cmd(fmt, {})
	cmd.range = { tbl.line1, tbl.line2 }
	vim.cmd(cmd)
end, { desc = "Align input lines", nargs = 1, range = true })
