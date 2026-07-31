local M = {}

local _async = nil
local function async_mod()
	if not _async then
		_async = require('alex.async')
	end
	return _async
end

---@alias alex.async.nursery.ExceptionPolicy 'ignore'|'cancel_siblings'|'rethrow'

---@class alex.async.nursery.Nursery
---@field private tasks alex.async.Task[]
---@field private running integer
---@field private done alex.async.Mpsc
---@field private policy alex.async.nursery.ExceptionPolicy
---@field private mutex alex.async.Mutex
M.Nursery = {}
M.Nursery.__index = M.Nursery

---@param policy? alex.async.nursery.ExceptionPolicy
---@return alex.async.nursery.Nursery
function M.Nursery.new(policy)
	local async = async_mod()
	return setmetatable({
		tasks = {},
		running = 0,
		done = async.Mpsc.new(),
		policy = policy or 'rethrow',
		mutex = async.Mutex.new()
	}, M.Nursery)
end

function M.Nursery:cancel()
	self.mutex:with_lock(function()
		for _, task in pairs(self.tasks) do
			task:cancel()
		end
	end):await()
	self:wait('ignore')
end

---@async
---@param policy? alex.async.nursery.ExceptionPolicy
function M.Nursery:wait(policy)
	self.mutex:with_lock(function()
		policy = policy or self.policy
		local err = nil
		while self.running > 0 do
			local ok, result = self.done:pop()
			assert (ok)
			self.running = self.running - 1
			err = err or result.err
			if result.err and policy == 'cancel_siblings' then
				for _, task in pairs(self.tasks) do
					task:cancel()
				end
			end
		end
		self.tasks = {}
		if err and policy ~= 'ignore' then
			error(err[1])
		end
	end):await()
end

---@param onstart fun()
---@return alex.async.Task
function M.Nursery:spawn(onstart, ...)
	local async = async_mod()
	local task = async.Task.start(onstart, ...)
	task:future():listen(function()
		self.done:push {}
	end, function(rej)
		self.done:push { err = rej }
	end)
	self.tasks[#self.tasks+1] = task
	self.running = self.running + 1
	return task
end

---@param f fun(alex.async.nursery.Nursery): any
---@param policy alex.async.nursery.ExceptionPolicy
---@return alex.async.Future
function M.with_nursery(f, policy)
	local async = async_mod()
	return async.Task.start(function()
		local nursery = M.Nursery.new(policy)
		local main = nursery:spawn(f, nursery)
		nursery:wait()
		return main:future():await()
	end):future()
end

return M
