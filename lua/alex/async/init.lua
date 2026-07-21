local M = {}

local RESOLVED_UNRESOLVED = 0
local RESOLVED_RESOLVED = 1
local RESOLVED_ERROR = 2

---@class alex.async.Future
---@field private slot any
---@field private resolved 0|1|2
---@field private callbacks fun(val, number)[]
M.Future = {}
M.Future.__index = M.Future

---@private
---@param slot any
---@param resolved 1|2
function M.Future:raw_resolve(slot, resolved)
	assert(self.resolved == RESOLVED_UNRESOLVED)
	self.slot = slot
	self.resolved = resolved
	if #self.callbacks ~= 0 then
		local callbacks = self.callbacks
		self.callbacks = {}
		for _, listener in pairs(callbacks) do
			listener(slot, resolved)
		end
	end
end

function M.Future:resolve(...)
	self:raw_resolve(table.pack(...), RESOLVED_RESOLVED)
end

function M.Future:reject(err)
	self:raw_resolve(err, RESOLVED_ERROR)
end

---@param cb fun(res, rej)
---@return alex.async.Future
function M.Future:setup(cb)
	local function res(...)
		self:raw_resolve(table.pack(...), RESOLVED_RESOLVED)
	end
	local function rej(err)
		self:raw_resolve(err, RESOLVED_ERROR)
	end
	cb(res, rej)
	return self
end

---@return alex.async.Future
function M.Future:init()
	return setmetatable({
		resolved = RESOLVED_UNRESOLVED,
		callbacks = {}
	}, M.Future)
end

---@param cb fun(res, rej)
---@return alex.async.Future
function M.Future:new(cb)
	return M.Future:init():setup(cb)
end

---@return alex.async.Future
function M.Future:value(...)
	return setmetatable({
		slot = table.pack(...),
		resolved = RESOLVED_RESOLVED,
		callbacks = {}
	}, M.Future)
end

---@param err any
---@return alex.async.Future
function M.Future:err(err)
	return setmetatable({
		slot = err,
		resolved = RESOLVED_ERROR,
		callbacks = {}
	}, M.Future)
end

---@param res? fun(...)
---@param rej? fun(err)
function M.Future:listen(res, rej)
	local function onresrej(val, status)
		if status == RESOLVED_RESOLVED then
			if res then res(table.unpack(val, 1, val.n)) end
		elseif status == RESOLVED_ERROR then
			if rej then rej(val) end
		else
			error('invalid status : ' .. tostring(status))
		end
	end
	if self.resolved ~= RESOLVED_UNRESOLVED then
		onresrej(self.slot, self.resolved)
		return
	end
	self.callbacks[#self.callbacks+1] = onresrej
end

---@param res? fun(...): alex.async.Future
---@param rej? fun(err): alex.async.Future
---@return alex.async.Future
function M.Future:bind(res, rej)
	return M.Future:new(function(_res, _rej)
		self:listen(function (...)
			if res then res(...):listen(_res, _rej) else _res(...) end
		end, function (err)
			if rej then rej(err):listen(_res, _rej) else _rej(err) end
		end)
	end)
end

---@param next fun()
function M.Future:sequence(next)
	self:listen(next, next)
end

---@param rej fun(err): alex.async.Future
---@return alex.async.Future
function M.Future:catch(rej)
	return self:bind(nil, rej)
end

---@return boolean
function M.Future:isresolved()
	return self.resolved ~= RESOLVED_UNRESOLVED
end

---@class alex.async.Task
---@field thread thread
---@field cancelled boolean
---@field result alex.async.Future
---@field cached_resume table?
M.Task = {}
M.Task.__index = M.Task

---@type alex.async.Task?
local running_task = nil

---@return boolean
function M.Task:running()
	return running_task ~= nil and coroutine.running() == running_task.thread
end

---@return boolean
function M.Task:currently_running()
	return self == running_task
end

---@return alex.async.Task
function M.Task:get_running()
	assert(running_task, 'async task must be running')
	return running_task
end

---@async
---@return ...
function M.Task:suspend()
	local t
	if self.cached_resume then
		t = self.cached_resume
		self.cached_resume = nil
	else
		t = table.pack(coroutine.yield())
	end
	assert(t)
	if not t[1] then
		error(t[2])
	end
	return table.unpack(t, 2, t.n)
end

---@param ok boolean
---@return alex.async.Task
function M.Task:raw_resume(ok, ...)
	if self:currently_running() then
		assert(self.cached_resume == nil)
		self.cached_resume = table.pack(ok, ...)
		return self
	end
	local status = coroutine.status(self.thread)
	assert(status ~= 'running')
	assert(status ~= 'dead')
	local parent = running_task
	running_task = self
	local rok, err = coroutine.resume(self.thread, ok, ...)
	running_task = parent
	if not rok then
		self.result:reject(err)
	end
	return self
end

function M.Task:resume(...)
	return self:raw_resume(true, ...)
end

function M.Task:resume_err(...)
	return self:raw_resume(false, ...)
end

---@param onstart function
---@return alex.async.Task
function M.Task:new(onstart)
	local future = M.Future:init()
	local thread = coroutine.create(function(ok, ...)
		assert(ok)
		future:resolve(onstart(...))
	end)
	local task = setmetatable({
		thread = thread,
		cancelled = false,
		result = future
	}, M.Task)
	return task
end

---@param onstart function
---@return alex.async.Task
function M.Task:start(onstart, ...)
	return M.Task:new(onstart):resume(...)
end

---@return alex.async.Future
function M.Task:future()
	return self.result
end

function M.Task:cancel()
	self.cancelled = true
end

---@async
---@return ...
function M.Future:await()
	local task = M.Task:get_running()
	self:listen(function(...)
		task:resume(...)
	end, function(rej)
		task:resume_err(rej)
	end)
	return task:suspend()
end

---@async
---@return ...
function M.callback_suspend(cb)
	local task = M.Task:get_running()
	cb(function(...)
		task:resume(...)
	end)
	return task:suspend()
end

---@return alex.async.Future
function M.callback_wrap(cb)
	return M.Future:new(function(res)
		cb(res)
	end)
end

---@async
function M.yield()
	M.callback_suspend(vim.schedule)
end

---@param timeout number ms
---@return alex.async.Future
function M.sleep(timeout)
	return M.Future:new(function(res)
		vim.defer_fn(res, timeout)
	end)
end

---@async
---@return boolean ok
---@return any ...
function M.pcall(fun, ...)
	local args = table.pack(...)
	local task = M.Task:start(function()
		return fun(table.unpack(args, 1, args.n))
	end)
	local current = M.Task:get_running()
	task:future():listen(function (...)
		current:resume(true, ...)
	end, function(err)
		current:resume(false, err)
	end)
	return current:suspend()
end

---@param futs alex.async.Future[]
---@return alex.async.Future
function M.all(futs)
	local ret = M.Future:init()
	local count = #futs
	for _, fut in pairs(futs) do
		fut:sequence(function()
			count = count - 1
			if count == 0 then
				ret:resolve()
			end
		end)
	end
	return ret
end

---@param fut alex.async.Future
---@param timeout number ms
---@return alex.async.Future
function M.timeout(fut, timeout)
	local f = M.Future:init()
	local timer = vim.defer_fn(function()
		f:resolve(false)
	end, timeout)
	fut:listen(function(...)
		if not f:isresolved() then
			timer:stop(); timer:close()
			f:resolve(true, ...)
		end
	end, function(rej)
		if not f:isresolved() then
			timer:stop(); timer:close()
			f:reject(rej)
		end
	end)
	return f
end

---@class alex.async.Semaphore
---@field private cur number
---@field private waiters function[]
M.Semaphore = {}
M.Semaphore.__index = M.Semaphore

---@param cur number?
---@return alex.async.Semaphore
function M.Semaphore:new(cur)
	return setmetatable({
		cur = cur or 0,
		waiters = {}
	}, M.Semaphore)
end

function M.Semaphore:signal()
	if #self.waiters ~= 0 then
		local waiter = table.remove(self.waiters, 1)
		waiter()
		return
	end
	self.cur = self.cur + 1
end

---@return alex.async.Future
function M.Semaphore:wait()
	if self:try_wait() then
		return M.Future:value()
	end
	return M.Future:new(function(res)
		self.waiters[#self.waiters+1] = res
	end)
end

---@return boolean
function M.Semaphore:try_wait()
	if self.cur > 0 then
		self.cur = self.cur - 1
		return true
	end
	return false
end

---@class alex.async.Mpsc
---@field reader? alex.async.Task
---@field backing any[]
---@field limit alex.async.Semaphore
---@field closed boolean
M.Mpsc = {}
M.Mpsc.__index = M.Mpsc

---@param limit? number
function M.Mpsc:new(limit)
	limit = limit or math.huge
	return setmetatable({
		backing = {},
		limit = M.Semaphore:new(limit),
		closed = false
	}, M.Mpsc)
end

---@return alex.async.Future
function M.Mpsc:push(val)
	if self.closed then
		return M.Future:value(false)
	end
	local reader = self.reader
	if reader then
		self.reader = nil
		reader:resume(val)
		return M.Future:value(true)
	end
	return self.limit
		:wait()
		:bind(function()
			self.backing[#self.backing+1] = val
			return M.Future:value(true)
		end)
end

---@return boolean ok
---@return any ...
function M.Mpsc:pop()
	local task = M.Task:get_running()
	local ok, val = self:try_pop()
	if not ok then
		if self.closed then
			return false
		end
		assert(self.reader == nil)
		self.reader = task
		val = task:suspend()
	end
	return true, val
end

---@return boolean ok
---@return any ...
function M.Mpsc:try_pop()
	if #self.backing == 0 then
		return false
	end
	local val = table.remove(self.backing, 1)
	self.limit:signal()
	return true, val
end

function M.Mpsc:close()
	self.closed = true
	if self.reader then
		self.reader:resume(false)
		self.reader = nil
	end
end

---@class alex.Async.Actor
---@field private queue alex.async.Mpsc
---@field private thread alex.async.Task
M.Actor = {}
M.Actor.__index = M.Actor

function M.Actor:serve(onreq)
	while not self.thread.cancelled do
		local ok, req = self.queue:pop()
		if not ok then break end
		local result = table.pack(M.pcall(onreq, table.unpack(req.args, 1, req.args.n)))
		if not result[1] then
			req.fut:reject(result[2])
		else
			req.fut:resolve(table.unpack(result, 2, result.n))
		end
		M.yield()
	end
end

---@param onreq fun(any)
---@return alex.Async.Actor
function M.Actor:new(onreq)
	---@type alex.Async.Actor
	local actor
	local task = M.Task:new(function()
		actor:serve(onreq)
	end)
	actor = setmetatable({
		queue = M.Mpsc:new(1000),
		thread = task
	}, M.Actor)
	task:resume()
	return actor
end

---@return alex.async.Future
function M.Actor:request(...)
	local fut = M.Future:init()
	local req = {
		args = table.pack(...),
		fut = fut
	}
	self.queue:push(req)
	return fut
end

function M.Actor:close()
	self.queue:close()
end

---@return alex.async.Future
function M.Actor:wait()
	return self.thread:future()
end

M.vim = {}
---@param cmd string[]
---@param opts vim.SystemOpts?
---@return vim.SystemObj obj
---@return alex.async.Future on_exit
function M.vim.system(cmd, opts)
	local obj
	local fut = M.callback_wrap(function(cb)
		if opts then
			obj = vim.system(cmd, opts, cb)
		else
			obj = vim.system(cmd, cb)
		end
	end)
	assert(obj)
	return obj, fut
end

M.nursery = require('alex.async.nursery')
return M
