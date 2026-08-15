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

---@class alex.repl.buffer.HistoryEntry
---@field line1 integer
---@field line2 integer
---@field lines string[]

---@alias alex.repl.buffer.History alex.repl.buffer.HistoryEntry[]

---@class alex.repl.buffer.Repl
---@field ns integer
---@field filetype string
---@field view integer
---@field view_win integer
---@field input integer
---@field input_win integer
---@field actor alex.async.Actor
---@field history alex.repl.buffer.History
---@field argv string[]
---@field on_start_cb? fun(self: self)
---@field setup_buf_cb? fun(integer)
---@field shutdown_buf_cb? fun(integer)
M.Repl = {}
M.Repl.__index = M.Repl

---@param view integer
---@param input integer
local function set_buffer_opts(view, input)
	vim.bo[view].swapfile = false
	vim.bo[view].buftype = 'nofile'
	vim.bo[view].modifiable = false
	vim.bo[view].bufhidden = 'hide'
	vim.bo[input].swapfile = false
	vim.bo[input].buftype = 'nofile'
	vim.bo[input].bufhidden = 'hide'
end

---@param view integer
---@param input integer
local function open_windows(view, input)
	local height = math.floor(vim.o.lines / 2)
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
	return view_win, input_win
end

---@param win integer
---@param buf? integer
local function scroll_bottom(win, buf)
	buf = buf or vim.api.nvim_win_get_buf(win)
	local pos = vim.api.nvim_win_get_cursor(win)
	pos[1] = vim.api.nvim_buf_line_count(buf)
	vim.api.nvim_win_set_cursor(win, pos)
end

---@param view integer
---@param lines string[]
local function append_view(view, lines)
	vim.bo[view].modifiable = true
	vim.api.nvim_buf_set_lines(view, -1, -1, false, lines)
	vim.bo[view].modifiable = false
end

---@param view integer
---@param ns integer
---@param lines string[]
---@param history alex.repl.buffer.History
local function append_view_history(view, ns, lines, history)
	vim.bo[view].modifiable = true
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
end

---@class alex.repl.buffer.ReplOpts
---@field on_start? fun(alex.repl.buffer.Repl)
---@field setup_buf? fun(integer)
---@field shutdown_buf? fun(integer)

---@param filetype string
---@param argv string[]
---@param opts? alex.repl.buffer.ReplOpts
---@return alex.repl.buffer.Repl
function M.Repl.new(filetype, argv, opts)
	opts = opts or {}
	local ns = vim.api.nvim_create_namespace('repl://' .. filetype .. '/namespace')
	local self = setmetatable({
		ns = ns,
		filetype = filetype,
		view = -1,
		view_win = -1,
		input = -1,
		input_win = -1,
		history = {},
		argv = argv,
		on_start_cb = opts.on_start,
		setup_buf_cb = opts.setup_buf,
		shutdown_buf_cb = opts.shutdown_buf
	}, M.Repl)
	return self
end

---@param self alex.repl.buffer.Repl
local function install_buffer_autocmds(self)
	vim.api.nvim_create_autocmd('BufWipeout', {
		buf = self.view,
		once = true,
		callback = function()
			self.view = -1
			self.view_win = -1
			if self.input ~= -1 then
				vim.api.nvim_buf_delete(self.input, { force = true })
			end
			self.actor:shutdown()
		end
	})
	vim.api.nvim_create_autocmd('BufWipeout', {
		buf = self.input,
		once = true,
		callback = function()
			self.input = -1
			self.input_win = -1
		end
	})
end

local function install_window_autocmds(self)
	vim.api.nvim_create_autocmd('WinClosed', {
		pattern = tostring(self.view_win),
		once = true,
		callback = function()
			self.view_win = -1
		end
	})
	vim.api.nvim_create_autocmd('WinClosed', {
		pattern = tostring(self.input_win),
		once = true,
		callback = function()
			self.input_win = -1
		end
	})
end

function M.Repl:start()
	if self.view ~= -1 then
		return
	end
	local view_name = 'repl://' .. self.filetype .. '/view'
	local input_name = 'repl://' .. self.filetype .. '/input'
	self.view = create_or_reset(view_name, true, false)
	self.input = create_or_reset(input_name, false, true)
	vim.bo[self.input].filetype = self.filetype
	set_buffer_opts(self.view, self.input)
	self.actor = require('alex.repl.actor').server_actor(self.argv)
	vim.keymap.set('n', '<CR>', function()
		local lines = vim.api.nvim_buf_get_lines(self.input, 0, -1, false)
		vim.api.nvim_buf_set_lines(self.input, 0, -1, false, {})
		append_view_history(self.view, self.ns, lines, self.history)
		self.actor:request(table.concat(lines, '\n'))
			 :listen(function(resp)
				local rlines = vim.split(resp, '\n')
				append_view(self.view, rlines)
				scroll_bottom(self.view_win, self.view)
			 end)
			 :report_err()
	end, { buf = self.input })
	vim.keymap.set('n', '<CR>', function()
		local row = vim.fn.line('.', self.view_win) - 1
		for _, range in ipairs(self.history) do
			if range.line1 <= row and row < range.line2 then
				 vim.api.nvim_buf_set_lines(self.input, 0, -1, false, range.lines)
				 vim.api.nvim_set_current_win(self.input_win)
			end
		end
	end, { buf = self.view })
	install_buffer_autocmds(self)
	if self.on_start_cb then
		self:on_start_cb()
	end
end

function M.Repl:open()
	self:start()
	self:close()
	self.view_win, self.input_win = open_windows(self.view, self.input)
	install_window_autocmds(self)
end

function M.Repl:close()
	if vim.api.nvim_win_is_valid(self.view_win) then
		vim.api.nvim_win_close(self.view_win, true)
	end
	if vim.api.nvim_win_is_valid(self.input_win) then
		vim.api.nvim_win_close(self.input_win, true)
	end
end

function M.Repl:toggle()
	if vim.api.nvim_win_is_valid(self.view_win) then
		self:close()
	else
		self:open()
	end
end

function M.Repl:shutdown()
	vim.notify('repl shutdown')
	self.actor:shutdown()
end

---@param lines string[]
function M.Repl:send(lines)
	local req = table.concat(lines, '\n')
	self.actor:request(req):listen(function(res)
		if res == '' then res = '#void' end
		append_view(self.view, vim.split(res, '\n', { plain = true }))
		scroll_bottom(self.view_win, self.view)
	end):report_err()
end

---@param line string
function M.Repl:send_line(line)
	self.actor:request(line):listen(function(res)
		if res == '' then res = '#void' end
		append_view(self.view, vim.split(res, '\n', { plain = true }))
		scroll_bottom(self.view_win, self.view)
	end)
end

function M.scheme_repl()
	local repl = M.Repl.new('scheme', { 'scheme', '--script', config .. '/lua/alex/repl/scheme-inline-repl.scm' })
	function repl:on_start_cb()
		local complete_col = nil
		local obj = require('alex.vimffi').Object.new(function(findstart, base)
			if findstart == 1 then
				local line = vim.api.nvim_get_current_line()
				local col = vim.fn.col('.') - 1
				local start = line:sub(1, col):find('[a-zA-Z0-9_<>-]+$')
				complete_col = start and start - 1 or col
				return complete_col
			end
			self.actor:request(
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
		local bufs = { self.input }
		local function clear_compl()
			for _, buf in ipairs(bufs) do
				if vim.api.nvim_buf_is_valid(buf) then
					vim.bo[buf].omnifunc = nil
				end
			end
		end
		local name = obj:vim_script_name()
		vim.bo[self.input].omnifunc = name
		vim.api.nvim_create_autocmd('BufDelete', {
			buf = self.view,
			callback = clear_compl
		})
		vim.api.nvim_create_autocmd('BufDelete', {
			buf = self.input,
			callback = clear_compl
		})
		self.setup_buf_cb = function(buf)
			vim.bo[buf].omnifunc = name
			bufs[#bufs+1] = buf
		end
	end
	return repl
end

function M.python_repl()
	return M.Repl.new('python', { 'python', config .. '/lua/alex/repl/python-inline-repl.py' })
end

return M
