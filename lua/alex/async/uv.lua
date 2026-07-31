local M = {}

local uv = vim.uv
local _async
local function async_mod()
	if not _async then
		_async = require('alex.async')
	end
	return _async
end

---@async
---@param f fun(cb: fun())
---@return any ...
local function wrap(f)
	return async_mod().callback_suspend(f)
end

---@async
---@param handle uv.uv_handle_t
function M.close(handle)
	return wrap(function(cb)
		uv.close(handle, cb)
	end)
end

---@async
---@param  stream            uv.uv_stream_t
---@param  data              uv.buffer
---@return string|nil err
function M.write(stream, data)
	return wrap(function(cb)
		local ok, msg = uv.write(stream, data, cb)
		if not ok then
			error(msg)
		end
	end)
end

---@async
---@return 0|nil
---@return string|nil err
function M.listen_once_and_close(stream, client)
	local async = async_mod()
	local task = async.Task.get_running()
	local ok, msg = uv.listen(stream, 1, function(err)
		if err then
			task:resume(nil, err)
			return
		end
		local success = stream:accept(client)
		assert(success)
		stream:close(function()
			task:resume(0)
		end)
	end)
	if not ok then
		stream:close()
		return nil, msg
	end
	return task:suspend()
end

---@param  stream            uv.uv_stream_t
---@return string|nil err
function M.shutdown(stream)
	return async_mod().callback_suspend(function(cb)
		local ok, msg = uv.shutdown(stream, cb)
		if not ok then
			error(msg)
		end
	end)
end

return M
