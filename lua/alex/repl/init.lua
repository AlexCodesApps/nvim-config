local M = {}
local api = require('alex.api')

---@class alex.repl.Req
---@field input string|string[]
---@field cb fun(err: string|nil, data?: string)

---@param i integer
---@return string
local function int_to_be_64bit(i)
	local tbl = {}
	for s=1,4 do
		local shift = (4 - s) * 8
		local mask = bit.lshift(0xFF, shift)
		local bits = bit.band(i, mask)
		bits = bit.rshift(bits, shift)
		tbl[#tbl + 1] = bits
	end
	return string.char(0, 0, 0, 0, unpack(tbl))
end

---@param s string
---@return integer
local function be_64bit_to_int(s)
	local a, b, c, d, e, f, g, h = s:byte(1, 8)
	assert(bit.bor(a, b, c, d) == 0)
	return bit.lshift(e, 24) + bit.lshift(f, 16) + bit.lshift(g, 8) + h
end

---@param input string|string[]
---@return string
local function coerce_str(input)
	if type(input) == 'table' then
		input = table.concat(input, '\n')
	end
	return input
end

---@param args string[]
---@return alex.api.Queue
local function repl_queue(args)
	local builder = {}
	local builder_err = nil
	local proc = vim.system(args, {
		stdin = true,
		stdout = function(err, data)
			if err then builder_err = err end
			if data then table.insert(builder, data) end
		end,
		stderr = function(err, data)
			vim.notify(data)
		end
	})
	local function yield()
		local co = coroutine.running()
		assert(co)
		vim.schedule(function()
			coroutine.resume(co)
		end)
		coroutine.yield()
	end
	local function read(len)
		local out = {}
		local remain = len
		::continue::
		while not builder_err and remain ~= 0 do
			if #builder == 0 then
				yield()
				goto continue
			end
			local fst = builder[1]
			if fst:len() <= remain then
				remain = remain - fst:len()
				out[#out + 1] = fst
				table.remove(builder, 1)
				goto continue
			end
			out[#out + 1] = string.sub(fst, 1, remain)
			builder[1] = string.sub(fst, remain+1)
			break
		end
		return table.concat(out), builder_err
	end
	---@param req alex.repl.Req
	local queue = api.queue.new(function(req)
		local input = coerce_str(req.input)
		proc:write(int_to_be_64bit(input:len()))
		proc:write(input)

		local bytes, err = read(8)
		if err then vim.req.cb(err, nil) end
		local len = be_64bit_to_int(bytes)
		bytes, err = read(len)
		if err then req.cb(err, nil) return end
		req.cb(nil, bytes)
	end, function()
		proc:kill('sigterm')
		proc:wait()
	end)
	return queue
end

---@return alex.api.Queue
local function vim_queue()
	---@param req alex.repl.Req
	return api.queue.new(function(req)
		local input = coerce_str(req.input)
		local output = vim.inspect(vim.fn.eval(input))
		req.cb(nil, output)
	end)
end


---@return alex.api.Queue
local function lua_queue()
	return api.queue.new(function(req)
		local input = coerce_str(req.input)
		local chunk, err = loadstring('return ' .. input)
		if not chunk then
			req.cb(err, nil)
			return
		end
		local output = vim.inspect(chunk())
		req.cb(nil, output)
	end)
end

local python_repl_path =
	vim.fn.stdpath('config') .. '/lua/alex/repl/python_repl.py'
local scheme_repl_path =
	vim.fn.stdpath('config') .. '/lua/alex/repl/scheme_repl.scm'

---@return alex.api.Queue
local function python_queue()
	return repl_queue {'python', python_repl_path}
end

---@return alex.api.Queue
local function scheme_queue()
	return repl_queue {'scheme', scheme_repl_path}
end

local ft_table = {
	vim = vim_queue,
	lua = lua_queue,
	python = python_queue,
	-- scheme = scheme_queue,
}

local ns = vim.api.nvim_create_namespace('InlineEvalText')
local cache = {}

---@param line1 integer
---@param line2 integer
---@param cb fun(text: string[])
function M.eval_range(line1, line2, cb)
	local bufnr = vim.fn.bufnr()
	if not cache[bufnr] then
		local queue_fn = ft_table[vim.bo.filetype]
		if not queue_fn then
			vim.notify("can't find eval providor for " .. vim.bo.filetype)
			return
		end
		cache[bufnr] = queue_fn()
		vim.api.nvim_create_autocmd('BufDelete', {
			buffer = bufnr,
			once = true,
			callback = function()
				cache[bufnr]:close()
				cache[bufnr] = nil
			end
		})
	end
	local lines = vim.api.nvim_buf_get_lines(bufnr, line1-1, line2, false)
	cache[bufnr]:push({
		input = lines,
		cb = function(err, data)
			local text = vim.split(data or err, '\n', {
				plain = true,
				trimempty = true,
			})
			cb(text)
		end
	})
end

---@param line1 integer
---@param line2 integer
function M.inline_eval(line1, line2)
	vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
	M.eval_range(line1, line2, function(text)
		if #text == 1 then
			vim.api.nvim_buf_set_extmark(0, ns, line2-1, 0, {
				virt_text = {{'# ', 'Conceal'}, {text[1], 'Conceal'}}
			})
		else
			text = vim.tbl_map(function(line)
				return {{'# ', 'Conceal'}, { line , 'Conceal' }}
			end, text)
			vim.api.nvim_buf_set_extmark(0, ns, line2-1, 0, {
				virt_lines = text
			})
		end
		vim.api.nvim_create_autocmd({'TextChanged', 'TextChangedI', 'InsertEnter'}, {
			buffer = 0,
			once = true,
			callback = function()
				vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
			end
		})
	end)
end

function M.eval_in_buffer(line1, line2)
	M.eval_range(line1, line2, function(text)
		vim.cmd.new()
		vim.api.nvim_buf_set_lines(0, 0, -1, false, text)
	end)
end

function M.clear_cache()
	for _, entry in pairs(cache) do
		entry:close()
	end
	cache = {}
	M.repl_cache = cache
end

M.repl_cache = cache
return M
