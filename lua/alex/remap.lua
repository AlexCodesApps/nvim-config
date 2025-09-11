local config_path = vim.fn.stdpath('config')
vim.g.mapleader = ' '
vim.keymap.set('n', '<leader>ee', ':Ex<CR>')
vim.keymap.set('n', '<leader>ec', ':Ex ' .. config_path .. '<CR>')
vim.keymap.set('n', '<leader>;', [[mpA;<Esc>`p]])
vim.keymap.set('n', '<leader>,', [[mpA,<Esc>`p]])
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
vim.keymap.set('n', '<leader>fm', function()
	local cmd = { "apropos", ".*" }
	local output = vim.system(cmd, { text = true }):wait().stdout
	if output == nil then
		error("couldn't grab manpages")
	end
	local entries = {}
	for line in vim.gsplit(output, "\n") do
		local entry, part = string.match(line, "^([^%s]+)%s([^%s]+)")
		if entry then
			table.insert(entries, ffind.picker_entry.new(entry .. part, nil))
		end
	end
	local function on_select(selected, winmode)
		if not selected then return end
		if winmode ~= "none" then
			local table = {
				norm = "new",
				vert = "vnew",
			}
			vim.cmd(table[winmode])
		end
		vim.cmd("hide Man " .. selected.text)
	end
	ffind.open_picker(entries, {
		on_select = on_select
	})
end)

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
	vim.cmd("e " .. files[1])
end, {})
