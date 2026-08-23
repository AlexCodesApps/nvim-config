local M = {}
local _async = nil
local api = require('alex.api')
local function async_mod()
	if not _async then
		_async = require('alex.async')
	end
	return _async
end

---@class alex.async.stream.StreamReader
---@field partial string
---@field buffers alex.async.Mpsc
---@field read_lock alex.async.Mutex
M.StreamReader = {}
M.StreamReader.__index = M.StreamReader

---@param queue alex.async.Mpsc
---@return alex.async.stream.StreamReader
function M.StreamReader.new(queue)
	local async = async_mod()
	return setmetatable({
		partial = '',
		buffers = queue,
		read_lock = async.Mutex.new()
	}, M.StreamReader)
end

---@param onwrite fun(cb: fun(err?: string, data?: string))
---@return alex.async.stream.StreamReader
function M.StreamReader.new_cb(onwrite)
	local async = async_mod()
	local reader = setmetatable({
		partial = '',
		buffers = async.Mpsc.new(),
		read_lock = async.Mutex.new()
	}, M.StreamReader)
	onwrite(function(err, data)
		if data then
			reader.buffers:push({ true, data })
		elseif err then
			reader.buffers:push({ false, err })
		else
			reader.buffers:shutdown()
		end
	end)
	return reader
end

---@param stream uv.uv_stream_t
---@return alex.async.stream.StreamReader
function M.StreamReader.from_stream_start(stream)
	return M.StreamReader.new_cb(function(cb)
		local ok, err = stream:read_start(cb)
		if not ok then error(err) end
	end)
end

---@private
---@return boolean
---@return ... any
function M.StreamReader:next_chunk()
	local ok, next = self.buffers:pop()
	if not ok then return false end
	if not next[1] then
		error(next[2])
	end
	return true, next[2]
end

---@return alex.async.Future
function M.StreamReader:read(nbytes)
	return self.read_lock:with_lock(function()
		local builder = api.StringBuilder.from_str(self.partial)
		while nbytes > builder:len() do
			local ok, chunk = self:next_chunk()
			if not ok then
				self.partial = ''
				return builder:get()
			end
			builder:put(chunk)
		end
		local res
		res, self.partial = builder:get(nbytes, nil)
		return res
	end):yield_if_fast()
end

---@return alex.async.Future
function M.StreamReader:read_to_eof()
	return self.read_lock:with_lock(function()
		local builder = api.StringBuilder.from_str(self.partial)
		self.partial = ''
		while true do
			local ok, chunk = self:next_chunk()
			if not ok then break end
			builder:put(chunk)
		end
		builder:get()
	end):yield_if_fast()
end

---@param delim string
---@param keep? boolean
---@param plain? boolean
function M.StreamReader:read_to_delimiter(delim, keep, plain)
	local len = delim:len()
	local off = keep and 0 or len
	return self.read_lock:with_lock(function()
		local builder = api.StringBuilder.new()
		local last = self.partial
		while true do
			local idx = last:find(delim, nil, plain)
			if idx then
				local final = last:sub(1, idx-off)
				self.partial = last:sub(idx+len)
				builder:put(final)
				return builder:get()
			end
			builder:put(last)
			local ok, next = self:next_chunk()
			if not ok then
				self.partial = ''
				return builder:get()
			end
			last = next
		end
	end):yield_if_fast()
end

---@param keep_newline? boolean
---@return alex.async.Future
function M.StreamReader:read_line(keep_newline)
	return self:read_to_delimiter('\n', keep_newline, true)
end

---@return boolean
function M.StreamReader:is_eof()
	return self.partial == ''
		and self.buffers:is_empty()
end

return M
