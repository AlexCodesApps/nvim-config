local M = {}

local state = {}

local uv = vim.uv or vim.loop

function M.home_dir()
	if not state.home then
---@diagnostic disable-next-line: undefined-field
		state.home = uv.os_homedir()
	end
	return state.home
end

---@param filename string
---@param mode? "none"|"norm"|"vert"
function M.edit_file(filename, mode)
	mode = mode or "none"
	local tbl = {
		none = "edit ",
		norm = "new ",
		vert = "vnew "
	}
	local cmd = tbl[mode] .. vim.fn.fnameescape(filename)
	vim.cmd(cmd)
end

---@class alex.api.Queue
---@field private tasks any[]
---@field private onreq fun(any)
---@field private onclose? fun()
---@field private start_contcb boolean
---@field closed boolean
M.queue = {}
M.queue.__index = M.queue

local function next(queue)
	local req = table.remove(queue.tasks, 1)
	if req == nil then
		queue.start_contcb = true
		if queue.closed and queue.onclose then
			queue.onclose()
		end
		return
	end
	local co = coroutine.create(function()
		queue.onreq(req)
		return next(queue)
	end)
	coroutine.resume(co)
end

---@param onreq fun(any)
---@param onclose? fun()
function M.queue.new(onreq, onclose)
	return setmetatable({
		tasks = {},
		onreq = onreq,
		onclose = onclose,
		start_contcb = true
	}, M.queue)
end

---@return boolean
function M.queue:push(req)
	if self.closed then
		return false
	end
	self.tasks[#self.tasks + 1] = req
	if self.start_contcb then
		self.start_contcb = false
		vim.schedule(function()
			next(self)
		end)
	end
	return true
end

function M.queue:close()
	if self.closed then return end
	self.closed = true
	if not self.onclose then return end
	if self.start_contcb then
		self.onclose()
	end
end

return M
