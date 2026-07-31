local M = {}
local config = vim.fn.stdpath 'config'

local function find_buffer(name)
	for _, buf in pairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_get_name(buf) == name then
			return buf
		end
	end
	return -1
end

local function create_or_reset(name, listed, scratch)
	local found = find_buffer(name)
	if found ~= -1 then
		vim.api.nvim_buf_delete(found, {
			force = true
		})
	end
	local buf = vim.api.nvim_create_buf(listed, scratch)
	vim.api.nvim_buf_set_name(buf, name)
	return buf
end

function M.buffer_repl(filetype, cmd)
	local view_name = 'repl://' .. filetype .. '/view'
	local input_name = 'repl://' .. filetype .. '/input'
	local ns_name = 'repl://' .. filetype .. '/namespace'
	local view = create_or_reset(view_name, true, false)
	local input = create_or_reset(input_name, false, true)
	vim.bo[view].swapfile = false
	vim.bo[view].buftype = 'nofile'
	vim.bo[view].modifiable = false
	vim.bo[view].bufhidden = 'hide'
	vim.bo[input].swapfile = false
	vim.bo[input].buftype = 'nofile'
	vim.bo[input].bufhidden = 'hide'
	vim.bo[input].filetype = filetype
	local ns = vim.api.nvim_create_namespace(ns_name)
	local actor = require('alex.repl.actor').server_actor(cmd)
	vim.api.nvim_create_autocmd('BufDelete', {
		buf = view,
		callback = function()
			actor:shutdown()
		end
	})
	local height = math.floor(vim.o.lines / 2)
	local history = {}
	local view_win = vim.api.nvim_open_win(view, false, { win = -1, vertical = true, height = height - 4 })
	local input_win = vim.api.nvim_open_win(input, false, {
		win = view_win,
		split = 'below',
		height = 4,
		style = 'minimal'
	})
	vim.wo[view_win].winfixbuf = true
	vim.wo[view_win].wrap = true
	vim.wo[input_win].winfixbuf = true
	vim.keymap.set('n', '<CR>', function()
		vim.bo[view].modifiable = true
		local lines = vim.api.nvim_buf_get_lines(input, 0, -1, false)
		vim.api.nvim_buf_set_lines(input, 0, -1, false, {})
		local view_input_begin = vim.api.nvim_buf_line_count(view)
		if view_input_begin == 1 and vim.api.nvim_buf_get_lines(view, 0, 1, true)[1] == '' then
			view_input_begin = 0
			 vim.api.nvim_buf_set_lines(view, 0, -1, true, lines)
		else
			 vim.api.nvim_buf_set_lines(view, -1, -1, false, lines)
		end
		local view_input_end = vim.api.nvim_buf_line_count(view)
		vim.api.nvim_buf_set_extmark(view, ns, view_input_begin, 0, {
			hl_group = 'NonText',
			end_row = view_input_end
		})
		history[#history+1] = {
			line1 = view_input_begin,
			line2 = view_input_end,
			lines = lines
		}
		vim.bo[view].modifiable = false
		actor:request(table.concat(lines, '\n'))
			 :listen(function(resp)
				vim.bo[view].modifiable = true
				local rlines = vim.split(resp, '\n')
				vim.api.nvim_buf_set_lines(view, -1, -1, false, rlines)
				local pos = vim.api.nvim_win_get_cursor(view_win)
				pos[1] = vim.api.nvim_buf_line_count(view)
				vim.api.nvim_win_set_cursor(view_win, pos)
				vim.bo[view].modifiable = false
			 end)
			 :report_err()
	end, { buf = input })
	vim.keymap.set('n', '<CR>', function()
		local row = vim.fn.line('.', view_win) - 1
		for _, range in pairs(history) do
			if range.line1 <= row and row < range.line2 then
				 vim.api.nvim_buf_set_lines(input, 0, -1, false, range.lines)
				 vim.api.nvim_set_current_win(input_win)
			end
		end
	end, { buf = view })
	if filetype == 'scheme' then
		local complete_col = nil
		local obj = require('alex.vimffi').Object.new(function(findstart, base)
			if findstart == 1 then
				local line = vim.api.nvim_get_current_line()
				local col = vim.fn.col('.') - 1
				local start = line:sub(1, col):find('[a-zA-Z0-9_-]+$')
				complete_col = start and start - 1 or col
				return complete_col
			end
			actor:request(
				[[(eval '(environment-symbols sandboxed-environment)
						 (interaction-environment))]])
				:listen(function(resp)
					---@cast resp string
					resp = resp:sub(2, -2)
					local words = vim.split(resp, '%s+')
					if base ~= '' then
						words = vim.fn.matchfuzzy(words, base)
					end
					assert(complete_col)
					vim.fn.complete(complete_col + 1, words)
				end)
			return -2
		end)
		vim.bo[input].omnifunc = obj:vim_script_name()
		vim.api.nvim_create_autocmd('BufDelete', {
			buf = view,
			callback = function()
				if vim.api.nvim_buf_is_valid(input) then
					vim.bo[input].omnifunc = nil
				end
				obj:del()
			end
		})
		vim.api.nvim_create_autocmd('BufDelete', {
			buf = input,
			callback = function()
				obj:del()
			end
		})
	end
	actor:wait():listen(function()
		if vim.api.nvim_win_is_valid(input_win) then
			vim.api.nvim_win_close(input_win, true)
		end
		if vim.api.nvim_buf_is_valid(input) then
			vim.api.nvim_buf_delete(input, { force = true })
		end
	end)
	return view, view_win, input, input_win
end

function SchemeRepl()
	M.buffer_repl('scheme', { 'scheme', '--script', config .. '/lua/alex/repl/scheme-inline-repl.scm' })
end

function PythonRepl()
	M.buffer_repl('python', { 'python', config .. '/lua/alex/repl/python-inline-repl.py' })
end

return M
