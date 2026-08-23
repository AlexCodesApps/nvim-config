local M = {}

local _pack = table.pack

---@param fst? integer
local function _unpack(tbl, fst)
	return table.unpack(tbl, fst, tbl.n)
end

local RESOLVED_UNRESOLVED = 0
local RESOLVED_RESOLVED = 1
local RESOLVED_ERROR = 2

---@class alex.async.Future
---@field private slot any
---@field private resolved 0|1|2
---@field private callbacks fun(val, number)[]
M.Future = {}
M.Future.__index = M.Future

local function report_err(err)
	local iter = vim.gsplit(tostring(err), '\n', {
		plain = true
	})
	local msg = vim.iter(iter)
					:map(function(line)
						return { line }
					end)
					:totable()
	vim.schedule(function()
		vim.api.nvim_echo(msg, true, {
			err = true
		})
	end)
end

---@param f fun(...)
---@param ... any
local function run_n_forget_cb(f, ...)
	local ok, err = pcall(f, ...)
	if ok then return end
	report_err(err)
end

---@private
---@param slot any
---@param resolved 1|2
function M.Future:raw_resolve(slot, resolved)
	if not (self.resolved == RESOLVED_UNRESOLVED) then
		local msg = vim.inspect({ msg = 'future has been resolved twice', old_resolve = self.resolved, old_slot = self.slot, new_resolve = resolved, new_slot = slot })
		error(msg)
	end
	self.slot = slot
	self.resolved = resolved
	if #self.callbacks ~= 0 then
		local callbacks = self.callbacks
		self.callbacks = {}
		for _, listener in pairs(callbacks) do
			run_n_forget_cb(listener, slot, resolved)
		end
	end
end

---@param ok boolean
---@param ... any
function M.Future:presolve(ok, ...)
	if ok then
		self:raw_resolve(_pack(...), RESOLVED_RESOLVED)
	else
		local err = ...
		self:raw_resolve(err, RESOLVED_ERROR)
	end
end

function M.Future:resolve(...)
	self:raw_resolve(_pack(...), RESOLVED_RESOLVED)
end

function M.Future:reject(err)
	self:raw_resolve(err, RESOLVED_ERROR)
end

---@param cb fun(res, rej)
---@return alex.async.Future
function M.Future:setup(cb)
	local function res(...)
		self:raw_resolve(_pack(...), RESOLVED_RESOLVED)
	end
	local function rej(err)
		self:raw_resolve(err, RESOLVED_ERROR)
	end
	cb(res, rej)
	return self
end

---@return alex.async.Future
function M.Future.init()
	return setmetatable({
		resolved = RESOLVED_UNRESOLVED,
		callbacks = {}
	}, M.Future)
end

---@param cb fun(res, rej)
---@return alex.async.Future
function M.Future.new(cb)
	return M.Future.init():setup(cb)
end

---@return alex.async.Future
function M.Future.value(...)
	return setmetatable({
		slot = _pack(...),
		resolved = RESOLVED_RESOLVED,
		callbacks = {}
	}, M.Future)
end

---@param err any
---@return alex.async.Future
function M.Future.err(err)
	return setmetatable({
		slot = err,
		resolved = RESOLVED_ERROR,
		callbacks = {}
	}, M.Future)
end

---@param res? fun(...)
---@param rej? fun(err)
---@return self
function M.Future:listen(res, rej)
	local function onresrej(val, status)
		if status == RESOLVED_RESOLVED then
			if res then res(_unpack(val)) end
		elseif status == RESOLVED_ERROR then
			if rej then rej(val) end
		else
			error('invalid status : ' .. tostring(status))
		end
	end
	if self.resolved ~= RESOLVED_UNRESOLVED then
		run_n_forget_cb(onresrej, self.slot, self.resolved)
		return self
	end
	self.callbacks[#self.callbacks+1] = onresrej
	return self
end

local function assert_is_future(x)
    assert(type(x) == "table", "expected Future")
    assert(getmetatable(x) == M.Future, "expected Future")
    return x
end

---@param res? fun(...): alex.async.Future
---@param rej? fun(err): alex.async.Future
---@return alex.async.Future
function M.Future:bind(res, rej)
	return M.Future.new(function(_res, _rej)
		self:listen(function (...)
			if not res then
				_res(...)
				return
			end
			local fut = res(...)
			if fut then
				assert_is_future(fut)
				fut:listen(_res, _rej)
			else
				_res()
			end
		end, function (err)
			if not rej then
				_rej(err)
				return
			end
			local fut = rej(err)
			if fut then
				assert_is_future(fut)
				fut:listen(_res, _rej)
			else
				_res()
			end
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

---@return self
function M.Future:report_err()
	return self:listen(nil, report_err)
end

---@param next fun(ok: boolean, ...: any): alex.async.Future
---@return alex.async.Future
function M.Future:pbind(next)
	return self:bind(function(...)
		return next(true, ...)
	end, function(rej)
		return next(false, rej)
	end)
end

---@return alex.async.Future
function M.Future:yield_if_fast()
	return self:pbind(function(ok, ...)
		if not vim.in_fast_event() then
			return self
		end
		local args = _pack(ok, ...)
		local fut = M.Future.init()
		vim.schedule(function()
			fut:presolve(_unpack(args))
		end)
		return fut
	end)
end

---@param timeout? integer
function M.Future:sync_wait(timeout)
	timeout = timeout or 3000
	local function poll()
		return self:isresolved()
	end
	local ok = vim.wait(timeout, poll, 10)
	if not ok then
		error('timeout')
	else
		if self.resolved == RESOLVED_ERROR then
			error(self.slot)
		else
			assert(self.resolved == RESOLVED_RESOLVED)
			return _unpack(self.slot)
		end
	end
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
function M.Task.running()
	return running_task ~= nil and coroutine.running() == running_task.thread
end

---@return boolean
function M.Task:currently_running()
	return self == running_task
end

---@return alex.async.Task
function M.Task.get_running()
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
		t = _pack(coroutine.yield())
	end
	assert(t)
	if not t[1] then
		error(t[2])
	end
	return _unpack(t, 2)
end

---@param ok boolean
---@return self
function M.Task:raw_resume(ok, ...)
	if self:currently_running() then
		assert(self.cached_resume == nil)
		self.cached_resume = _pack(ok, ...)
		return self
	end
	local status = coroutine.status(self.thread)
	assert(status ~= 'running')
	assert(status ~= 'dead')
	local parent = running_task
	running_task = self
	local result = _pack(coroutine.resume(self.thread, ok, ...))
	running_task = parent
	if not result[1] then
		self.result:reject(result[2])
	elseif coroutine.status(self.thread) == 'dead' then
		self.result:resolve(_unpack(result, 2))
	end
	return self
end


---@return self
function M.Task:resume(...)
	return self:raw_resume(true, ...)
end


---@return self
function M.Task:resume_err(...)
	return self:raw_resume(false, ...)
end

---@param onstart function
---@return alex.async.Task
function M.Task.new(onstart)
	local future = M.Future.init()
	local thread = coroutine.create(function(ok, ...)
		assert(ok)
		return onstart(...)
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
function M.Task.start(onstart, ...)
	return M.Task.new(onstart):resume(...)
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
	local task = M.Task.get_running()
	self:listen(function(...)
		task:resume(...)
	end, function(rej)
		task:resume_err(rej)
	end)
	return task:suspend()
end

---@async
---@param cb fun(cb: fun(...): ...)
---@return ...
function M.callback_suspend(cb)
	local task = M.Task.get_running()
	cb(function(...)
		task:resume(...)
	end)
	return task:suspend()
end

---@async
function M.yield()
	M.callback_suspend(vim.schedule)
end


---@async
function M.yield_if_fast()
	if vim.in_fast_event() then
		M.yield()
	end
end

---@param timeout number ms
---@return alex.async.Future
function M.sleep(timeout)
	return M.Future.new(function(res)
		vim.defer_fn(res, timeout)
	end)
end

---@async
---@return boolean ok
---@return any ...
function M.copcall(fun, ...)
	local args = _pack(...)
	local task = M.Task.start(function()
		return fun(_unpack(args))
	end)
	local current = M.Task.get_running()
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
	if #futs == 0 then
		return M.Future.value()
	end
	local ret = M.Future.init()
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
	local f = M.Future.init()
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
function M.Semaphore.new(cur)
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

function M.Semaphore:signal_all()
	if #self.waiters == 0 then return end
	local waiters = self.waiters
	self.waiters = {}
	for _, waiter in pairs(waiters) do
		waiter()
	end
end

---@return alex.async.Future
function M.Semaphore:wait()
	if self:try_wait() then
		return M.Future.value()
	end
	return M.Future.new(function(res)
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

---@class alex.async.Mutex
---@field locked boolean
---@field waiters function[]
M.Mutex = {}
M.Mutex.__index = M.Mutex

function M.Mutex.new()
	return setmetatable({
		locked = false,
		waiters = {}
	}, M.Mutex)
end

---@return alex.async.Future
function M.Mutex:lock()
	if not self.locked then
		self.locked = true
		return M.Future.value()
	end
	return M.Future.new(function(res)
		self.waiters[#self.waiters+1] = res
	end)
end

function M.Mutex:unlock()
	if #self.waiters ~= 0 then
		vim.schedule(table.remove(self.waiters, 1))
	else
		self.locked = false
	end
end

function M.Mutex:try_lock()
	if not self.locked then
		self.locked = true
		return true
	end
	return false
end

---@return alex.async.Future
function M.Mutex:with_lock(f)
	local function body()
		self:lock():await()
		local results = _pack(M.copcall(f))
		self:unlock()
		if not results[1] then
			error(results[2])
		end
		return _unpack(results, 2)
	end
	return M.Task.start(body):future()
end

---@class alex.async.Mpsc
---@field reader? alex.async.Task
---@field backing any[]
---@field cancelled boolean
M.Mpsc = {}
M.Mpsc.__index = M.Mpsc

function M.Mpsc.new()
	return setmetatable({
		backing = {},
		closed = false
	}, M.Mpsc)
end

---@return boolean
function M.Mpsc:push(val)
	if self.cancelled then
		return false
	end
	local reader = self.reader
	if reader then
		self.reader = nil
		reader:resume(true, val)
	else
		self.backing[#self.backing+1] = val
	end
	return true
end

---@return boolean ok
---@return any ...
function M.Mpsc:pop()
	local task = M.Task.get_running()
	local ok, val = self:try_pop()
	if not ok then
		if self.cancelled then
			return false
		end
		assert(self.reader == nil)
		self.reader = task
		return task:suspend()
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
	return true, val
end

function M.Mpsc:shutdown()
	if self.cancelled then return end
	self.cancelled = true
	local reader = self.reader
	if reader then
		self.reader = nil
		reader:resume(false)
	end
end

function M.Mpsc:is_empty()
	return self.cancelled
		and #self.backing == 0
end

function M.Mpsc:close()
	self:shutdown()
	self.backing = {}
end

---@class alex.async.Actor
---@field private queue alex.async.Mpsc
---@field private thread alex.async.Task
M.Actor = {}
M.Actor.__index = M.Actor

function M.Actor:serve(onreq)
	while not self.thread.cancelled and vim.v.exiting == vim.NIL do
		local ok, req = self.queue:pop()
		if not ok then break end
		req.fut:presolve(M.copcall(onreq, _unpack(req.args)))
		M.yield()
	end
	self.queue:shutdown()
	while true do
		local ok, req = self.queue:try_pop()
		if not ok then break end
		req.fut:reject('cancelled actor')
	end
end

---@param onreq fun(any): ...
---@return alex.async.Actor
function M.Actor.new(onreq)
	---@type alex.async.Actor
	local actor
	local task = M.Task.new(function()
		actor:serve(onreq)
	end)
	actor = setmetatable({
		queue = M.Mpsc.new(),
		thread = task
	}, M.Actor)
	task:resume()
	return actor
end

---@return alex.async.Future
function M.Actor:request(...)
	local fut = M.Future.init()
	local req = {
		args = _pack(...),
		fut = fut
	}
	self.queue:push(req)
	return fut
end

function M.Actor:shutdown()
	self.queue:shutdown()
end

function M.Actor:close()
	self.thread:cancel()
end

---@return alex.async.Future
function M.Actor:wait()
	return self.thread:future()
end

M.vim = { ui = {} }
---@param cmd string[]
---@param opts vim.SystemOpts?
---@return vim.SystemObj obj
---@return alex.async.Future on_exit
function M.vim.system(cmd, opts)
	local obj
	local fut = M.Future.new(function(res)
		if opts then
			obj = vim.system(cmd, opts, res)
		else
			obj = vim.system(cmd, res)
		end
	end)
	assert(obj)
	return obj, fut
end

--- on_choice fun(item: T|nil, idx: integer|nil)
---@generic T
---@param items T[]
---@param opts alex.overrides.SelectOpts
---@return alex.async.Future
function M.vim.ui.select(items, opts)
	return M.Future.new(function(res)
		vim.ui.select(items, opts, res)
	end)
end

M.nursery = require('alex.async.nursery')
M.stream = require('alex.async.stream')
M.uv = require('alex.async.uv')

return M
