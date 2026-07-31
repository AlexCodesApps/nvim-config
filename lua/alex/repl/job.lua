local M = {}

---@class alex.repl.job.Repl
---@field id integer
---@field augroup integer
---@field buf integer
---@field jid integer
---@field argv string[]
---@field escape_input fun(input: string[]): string[]|string
M.Repl = {}
M.Repl.__index = M.Repl

---@class alex.repl.job.ReplOpts
---@field escape_input (fun(input: string[]): string[]|string) | 'none' | 'backslash' | 'flatten'

local id_counter = 0
---@param name string
---@param argv string[]
---@param opts alex.repl.job.ReplOpts
---@return alex.repl.job.Repl?
function M.Repl.new(name, argv, opts)
	if #argv == 0 or vim.fn.executable(argv[1]) ~= 1 then
		return nil
	end
	local escape_input
	if opts.escape_input == 'none' then
		escape_input = function(input) return input end
	elseif opts.escape_input == 'backslash' then
		escape_input = function(input)
			local ret = {}
			for i=1,#input-1 do
				ret[i] = input[i] .. ' \\'
			end
			if #input ~= 0 then
				ret[#input] = input[#input]
			end
			ret[#ret+1] = ''
			return ret
		end
	elseif opts.escape_input == 'join' then
		escape_input = function(input)
			return table.concat(input, ' ')
		end
	elseif opts.escape_input == 'flatten' then
		escape_input = function(input)
			return table.concat(input, '\n')
		end
	else
		escape_input = opts.escape_input
	end
	local id = id_counter
	id_counter = id_counter + 1
	local augroup = vim.api.nvim_create_augroup(name .. 'Repl', {})
	local buf, jid = -1, -1
	return setmetatable({
		id = id,
		augroup = augroup,
		buf = buf,
		jid = jid,
		argv = argv,
		escape_input = escape_input
	}, M.Repl)
end

---@return boolean
function M.Repl:start()
	if self.jid ~= -1 and vim.fn.jobwait({self.jid}, 0)[1] ~= -1 then
		self:close()
	end
	if self.buf ~= -1 then
		return true
	end
	local buf = vim.api.nvim_create_buf(true, false)
	local jid = vim.api.nvim_buf_call(buf, function()
		return vim.fn.jobstart(self.argv, {
			on_stdout = function(_, _, _)
				local winid = vim.fn.bufwinid(buf)
				if winid == -1 or vim.api.nvim_get_current_win() == winid then
					return
				end
				vim.schedule(function()
					vim.api.nvim_win_call(winid, function()
						vim.cmd("normal! G")
					end)
				end)
			end,
			term = true,
		})
	end)
	assert(jid ~= 0)
	if jid == -1 then
		vim.api.nvim_buf_delete(buf, { force = true })
		return false
	end
	self.buf, self.jid = buf, jid
	vim.api.nvim_create_autocmd('BufDelete', {
		buf = buf,
		group = self.augroup,
		callback = function() self.buf = -1 ; self:close() end
	})
	vim.api.nvim_create_autocmd({ 'WinEnter', 'BufEnter' }, {
		buf = buf,
		group = self.augroup,
		command = 'startinsert!'
	})
	local function set(modes, lhs, rhs)
		return vim.keymap.set(modes, lhs, rhs, { buf = buf })
	end
	set({'x', 'i', 't'}, '<C-w>', '<C-\\><C-n><C-w>')
	set({'x', 'i', 't'}, '<C-h>', '<C-\\><C-n><C-w><C-h>')
	set({'x', 'i', 't'}, '<C-j>', '<C-\\><C-n><C-w><C-j>')
	set({'x', 'i', 't'}, '<C-k>', '<C-\\><C-n><C-w><C-k>')
	set({'x', 'i', 't'}, '<C-l>', '<C-\\><C-n><C-w><C-l>')
	return true
end

function M.Repl:close()
	vim.api.nvim_clear_autocmds {
		group = self.augroup
	}
	if self.jid ~= -1 then
		vim.fn.jobstop(self.jid)
		vim.fn.jobwait({self.jid})
	end
	if self.buf ~= -1 then
		pcall(vim.api.nvim_buf_delete, self.buf, { force = true })
	end
	self.buf, self.jid = -1, -1
end

---@param input string|string[]
function M.Repl:send_input(input)
	if not self:start() then return end
	if type(input) == 'string' then
		input = vim.split(input, '\n')
	else
		input = vim.deepcopy(input)
	end
	local escaped = self.escape_input(input)
	if type(escaped) ~= 'string' then
		escaped[#escaped + 1] = ''
		escaped = table.concat(escaped, '\n')
	else
		escaped = escaped .. '\n'
	end
	escaped = escaped:gsub('\t', '    ')
	vim.api.nvim_chan_send(self.jid, escaped)
end

---@param input string
function M.Repl:send_oneline_input(input)
	if not self:start() then return end
	local escaped = input:gsub('\t', '    ') .. '\n'
	vim.api.nvim_chan_send(self.jid, escaped)
end

---@param buf integer
function M.Repl:register_buffer(buf)
	vim.keymap.set('x', '<M-e>', function()
	   local region = vim.fn.getregion(vim.fn.getpos('v'), vim.fn.getpos('.'), {
		 type = vim.fn.mode(),
		 exclusive = false,
		 eol = false,
	   })
	   self:send_input(region)
	end, { buf = buf })
	vim.keymap.set('n', '<M-e>', function()
		 vim.treesitter.get_parser(buf):parse()
		local node = vim.treesitter.get_node()
		if not node then return end
		local srow, scol = node:start()
		local erow, ecol = node:end_()
		local region = vim.api.nvim_buf_get_text(buf, srow, scol, erow, ecol, {})
	   self:send_input(region)
	end, { buf = buf })
	vim.keymap.set('n', '<M-p>', 'vip<M-e><Esc>', { buf = buf, remap = true })
end

function M.Repl:open()
	if not self:start() then return end
	local buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_open_win(self.buf, false, {
		split = 'below',
		height = math.ceil(vim.o.columns / 13)
	})
	self:register_buffer(buf)
end

return M
