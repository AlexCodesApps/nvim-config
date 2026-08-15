require('alex.remap')

local cswitch = require('alex.cswitch')

vim.api.nvim_create_user_command('PackUpdate', function() vim.pack.update() end, {
	desc = 'Update installed vim.pack packages'
})
vim.api.nvim_create_user_command('PackShow', function() vim.pack.update(nil, { offline = true }) end, {
	desc = 'Show installed vim.pack packages'
})

vim.api.nvim_create_user_command('CSwitch', cswitch.cswitch, {
	desc = 'Switch between file pairs via cswitch'
})

local inline_repl = require('alex.repl.inline')

vim.api.nvim_create_user_command('ReplOpen', function()
	local repl_ = require('alex.repl')
	local repl = repl_.get_repl_for_buffer(0)
	if not repl then return end
	repl:open(0)
end, { desc = 'Open repl' })

vim.api.nvim_create_user_command('ReplClose', function()
	local repl_ = require('alex.repl')
	local repl = repl_.get_repl_for_buffer(0)
	if not repl then return end
	repl:close()
end, { desc = 'Close repl' })

vim.api.nvim_create_user_command('ReplToggle', function()
	local repl_ = require('alex.repl')
	local repl = repl_.get_repl_for_buffer(0)
	if not repl then return end
	repl:toggle(0)
end, { desc = 'Toggle repl' })



vim.api.nvim_create_user_command('ReplConnect', function()
	local repl_ = require('alex.repl')
	local repl = repl_.get_repl_for_buffer(0)
	if not repl then return end
	repl:setup_buffer(0)
end, { desc = 'Connect repl' })

vim.api.nvim_create_user_command('ReplEvalBuf', function()
	local repl_ = require('alex.repl')
	local repl = repl_.get_repl_for_buffer(0)
	if not repl then return end
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	repl:send(lines)
end, { desc = 'Eval buffer' })

vim.api.nvim_create_user_command('InlineEval', function(opts)
	inline_repl.inline_eval(opts.line1, opts.line2)
end, { range = true, desc = 'Evaluate range with filetype specific interpreter' })

vim.api.nvim_create_user_command('MkMdTable', function(opts)
	local input = vim.api.nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, true)
	if #input < 2 then return end
	local header = input[1]
	table.remove(input, 1)
	local header_list = vim.split(header, '|')
	local width = #header_list
	if width < 1 then return end
	local tbl = {}
	local padtbl = vim.tbl_map(string.len, header_list)
	for i=1, #input do
		local line = input[i]
		local items = vim.split(line, '|')
		if #items ~= width then
			vim.notify('Width of table is not regular!')
			return
		end
		for j=1,width do
			padtbl[j] =
				math.max(padtbl[j], items[j]:len())
		end
		tbl[i] = items
	end
	local function print_row(row)
		local o = ''
		for i=1, #row do
			local str = row[i]
			local mwidth = padtbl[i]
			local pad = mwidth - str:len() + 1
			for _=1,pad do
				str = str .. ' '
			end
			o = o .. '| ' .. str
		end
		o = o .. '|'
		return o
	end
	local output = {
		print_row(header_list)
	}
	local sep = '|'
	for _, itemw in ipairs(padtbl) do
		sep = sep .. '-'
		for _=1,itemw do
			sep = sep .. '-'
		end
		sep = sep .. '-|'
	end
	table.insert(output, sep)
	for _, row in ipairs(tbl) do
		table.insert(output, print_row(row))
	end
	vim.api.nvim_buf_set_lines(0, opts.line1 - 1, opts.line2, true, output)
end, { desc = 'Make markdown table', range = true })

vim.api.nvim_create_user_command('UnMkMdTable', function(opts)
	local input = vim.api.nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, true)
	if #input < 3 then return end
	table.remove(input, 2)
	local output = {}
	for _, line in ipairs(input) do
		local output_line = line
			:gsub('%s*|%s*', '|')
			:match('^|(.*)|$')
		if not output_line then
			vim.notify('Invalid syntax')
			return
		end
		table.insert(output, output_line)
	end
	vim.api.nvim_buf_set_lines(0, opts.line1 - 1, opts.line2, true, output)
end, { desc = 'Unmake markdown table', range = true })

vim.api.nvim_create_user_command('Pad', function(tbl)
	local count = tonumber(tbl.args)
	local fmt = [[s/.*/\=printf('%-]] .. count .. [[s', submatch(0))]]
	local cmd = vim.api.nvim_parse_cmd(fmt, {})
	cmd.range = { tbl.line1, tbl.line2 }
	vim.cmd(cmd)
end, { desc = 'Align input lines', nargs = 1, range = true })

vim.api.nvim_create_user_command('Focus', function()
	local function on_unfocused()
		vim.notify('FOCUS')
	end
	vim.keymap.set('n', '<leader>fc', on_unfocused);
	vim.keymap.set('n', '<leader>fr', on_unfocused);
	vim.keymap.set('n', '<leader>fh', on_unfocused);
	vim.keymap.set('n', '<leader>ft', on_unfocused);
end, { desc = 'Focus.' })

local swap_files_open_cmd = 'edit ' .. vim.fn.stdpath('state') .. '/swap'
vim.api.nvim_create_user_command('SwapFilesOpen', function()
	vim.cmd(swap_files_open_cmd)
end, { desc = 'Open swap file directory' })

vim.api.nvim_create_user_command('WrappedScroll', function()
	vim.keymap.set('n', 'j', 'gj', { buffer = true })
	vim.keymap.set('n', 'k', 'gk', { buffer = true })
end, { desc = 'Enable wrapped scrolling' })

vim.api.nvim_create_user_command('FzGrep', function(opt)
	local cwd = opt.args ~= ''
		and opt.args or vim.api.nvim_buf_get_name(0)
	local stats = vim.uv.fs_stat(cwd)
	if not stats then
		vim.notify('argument does not exist')
		return
	end
	if stats.type ~= 'directory' then
		cwd = vim.fs.dirname(cwd)
	end
	require('alex.ffind').grep_files {
		cwd = cwd,
		exclude_pattern = vim.g.ffind_exclude_pattern,
		gitignore = vim.g.ffind_gitignore == 1
	}
end, { desc = 'Fuzzy grep directory', nargs = '?', complete = 'file' })
