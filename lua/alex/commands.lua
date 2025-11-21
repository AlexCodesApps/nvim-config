require('alex.remap')

vim.api.nvim_create_user_command('CSwitch', function()
	local path = vim.api.nvim_buf_get_name(0)
	local filename, extension = path:gsub('\\', '/'):match([[/([^/]+)%.(%a+)$]])
	if not filename then
		vim.notify('no extension found')
		return
	end
	local ext_table = {
		['c'] = 'h',
		['h'] = 'c',
		['cpp'] = 'hpp',
		['hpp'] = 'cpp',
	}
	local extension2 = ext_table[extension]
	if extension2 == nil then
		vim.notify('unknown extension [.' .. extension .. ']')
		return
	end
	local files = vim.fn.findfile(filename .. '.' .. extension2, '**', -1)
	if #files == 0 then
		vim.notify('no candidates found')
		return
	end
	if #files ~= 1 then
		vim.notify('multiple candidates found')
		return
	end
	vim.cmd('e ' .. vim.fn.fnameescape(files[1]))
end, {})

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

local swap_files_open_cmd = 'Explore ' .. vim.fn.stdpath('state') .. '/swap'
vim.api.nvim_create_user_command('SwapFilesOpen', function()
	vim.cmd(swap_files_open_cmd)
end, {})
