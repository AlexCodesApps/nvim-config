local M = {}

---@class alex.repl.Interface
---@field inner any
---@field start fun(): boolean
---@field shutdown fun()
---@field open fun(): boolean
---@field close fun()
---@field toggle fun()
---@field send fun(lines: string[]): boolean
---@field send_line? fun(line: string): boolean
---@field eval? fun(input: string): alex.async.Future
---@field setup_buf? fun(integer)
---@field shutdown_buf? fun(integer)

---@class alex.repl.Client
---@field interface alex.repl.Interface
---@field private buffers integer[]
M.Client = {}
M.Client.__index = M.Client

---@param interface alex.repl.Interface
---@return alex.repl.Client
function M.Client.new(interface)
	return setmetatable({
		interface = interface,
		buffers = {}
	}, M.Client)
end

---@param buf integer
function M.Client:setup_buffer(buf)
	self.buffers[#self.buffers+1] = buf
	if self.interface.setup_buf then
		self.interface.setup_buf(buf)
	end
	local api = require('alex.api')
	vim.keymap.set({ 'n', 'x' }, '<M-e>', function()
		local lines
		local mode = api.mode_info()
		if api.mode_info_is_visual(mode) then
			lines = api.get_selection()
		else
			api.ensure_treesitter_parse()
			local node = vim.treesitter.get_node()
			if not node then return end
			lines = api.get_node_text(0, node)
		end
		self.interface.send(lines)
	end, { buf = buf })
	vim.keymap.set('n', '<M-p>', 'vip<M-e><Esc>', {
		buf = buf,
		remap = true
	})
end

---@param buf? integer
---@return boolean
function M.Client:open(buf)
	if not self.interface.open() then
		return false
	end
	if buf then
		self:setup_buffer(buf)
	end
	return true
end

---@param input string[]
function M.Client:send(input)
	self.interface.send(input)
end

---@param line string
function M.Client:send_line(line)
	if self.interface.send_line then
		self.interface.send_line(line)
		return
	end
	self.interface.send({ line })
end

function M.Client:close()
	self.interface.close()
end

---@param buf integer?
function M.Client:toggle(buf)
	if buf then
		self:setup_buffer(buf)
	end
	self.interface.toggle()
end

function M.Client:shutdown()
	for _, buf in pairs(self.buffers) do
		if vim.api.nvim_buf_is_valid(buf) then
			vim.keymap.del({ 'n', 'x' }, '<M-e>')
			vim.keymap.del('n', '<M-p>')
			if self.interface.shutdown_buf then
				self.interface.shutdown_buf(buf)
			end
		end
	end
	self.interface.shutdown()
end

local job = require('alex.repl.job')
---@param repl alex.repl.job.Repl?
---@return alex.repl.Client?
local function job_repl_client(repl)
	if not repl then return nil end
	---@type alex.repl.Interface
	local interface = {
		inner = repl,
		start = function()
			return repl:start()
		end,
		shutdown = function()
			repl:shutdown()
		end,
		open = function()
			return repl:open()
		end,
		close = function()
			repl:close()
		end,
		toggle = function()
			repl:toggle()
		end,
		send = function(lines)
			return repl:send(lines)
		end,
		send_line = function(line)
			return repl:send_line(line)
		end
	}
	return M.Client.new(interface)
end

local buffer_repl = require('alex.repl.buffer')
---@param repl alex.repl.buffer.Repl?
---@return alex.repl.Client?
local function buffer_repl_client(repl)
	if not repl then return nil end
	---@type alex.repl.Interface
	local interface = {
		start = function()
			return repl:start()
		end,
		shutdown = function()
			repl:shutdown()
		end,
		open = function()
			return repl:open()
		end,
		close = function()
			repl:close()
		end,
		toggle = function()
			repl:toggle()
		end,
		send = function(input)
			return repl:send(input)
		end,
		send_line = function(line)
			return repl:send_line(line)
		end,
		eval = function(input)
			return repl:eval(input)
		end,
		setup_buf = function(buf)
			if repl.setup_buf_cb then
				repl.setup_buf_cb(buf)
			end
		end,
		shutdown_buf = function(buf)
			if repl.shutdown_buf_cb then
				repl.shutdown_buf_cb(buf)
			end
		end,
	}
	return M.Client.new(interface)
end

local ghci_repl = nil

---@param input string[]
---@return string|string[]
local function escape_ghci_input(input)
	table.insert(input, 1, ':{')
	table.insert(input, ':}')
	return input
end

---@return alex.repl.Client?
function M.ghci_repl()
	if ghci_repl then return ghci_repl end
	ghci_repl = job_repl_client(job.Repl.new('GHCI', {'ghci'}, {
		escape_input = escape_ghci_input
	}))
	return ghci_repl
end

local cabal_repl = nil

---@return alex.repl.Client?
function M.cabal_repl()
	if cabal_repl then return cabal_repl end
	cabal_repl = job_repl_client(job.Repl.new('Cabal', {'cabal', 'repl'}, {
		escape_input = escape_ghci_input
	}))
	return cabal_repl
end

local scheme_repl = nil

---@return alex.repl.Client?
function M.scheme_repl()
	if scheme_repl then return scheme_repl end
	scheme_repl = buffer_repl_client(buffer_repl.scheme_repl())
	return scheme_repl
end


local lua_repl = nil

---@return alex.repl.Client?
function M.lua_repl()
	if lua_repl then return lua_repl end
	lua_repl = job_repl_client(job.Repl.new('Lua', {'lua'}, {
		escape_input = function(lines)
			local text = table.concat(lines, '\n')
			local tree = vim.treesitter.get_string_parser(text, 'lua')
							:parse()
			if tree then
				local root = tree[1]:root()
				if root:has_error() then
					return text
				end
				if root:named_child_count() == 1
					and root:named_child(0):type() == 'function_call' then
					return text
				end
			end
			return 'do ' .. text .. ' end'
		end
	}))
	return lua_repl
end

local node_repl = nil

---@return alex.repl.Client?
function M.node_repl()
	if node_repl then return node_repl end
	node_repl = job_repl_client(job.Repl.new('Node', {'node'}, {
		escape_input = 'none'
	}))
	return node_repl
end

local python_repl = nil
---@return alex.repl.Client?
function M.python_repl()
	if python_repl then return python_repl end
	python_repl = buffer_repl_client(buffer_repl.python_repl())
	return python_repl
end

---@type table<string, { repl: fun(): alex.repl.Client? }>
M.filetype_repl_table = {
	lua = { repl = M.lua_repl },
	scheme = { repl = M.scheme_repl },
	haskell = { repl = M.ghci_repl },
	javascript = { repl = M.node_repl },
	python = { repl = M.python_repl }
}

---@param buf integer
---@return alex.repl.Client?
function M.get_repl_for_buffer(buf)
	local entry = M.filetype_repl_table[vim.bo[buf].filetype]
	if not entry then return end
	return entry.repl()
end

return M
