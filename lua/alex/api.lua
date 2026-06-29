local M = {}

local state = {}

local uv = vim.uv or vim.loop

function M.home_dir()
	if not state.home then
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

do -- queue
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
end -- queue

---@param name string
function M.lsp_client_available(name)
	local config = vim.lsp.config[name]
	if not config or not config.cmd then return false end
	if type(config.cmd) ~= 'table' then return true end
	local relbin = config.cmd[1]
	local relbase = config.cmd_cwd
	local path
	if relbase and relbin:sub(1, 1) ~= '/' then
		path = vim.fs.joinpath(relbase, relbin)
	else
		path = relbin
	end
	return vim.fn.executable(path) == 1
end


---@param bufnr? integer
---@return boolean
function M.try_enable_clang_format(bufnr)
	if vim.fn.executable('clang-format') ~= 1 then
		M.try_enable_clang_format = function() end
		return false
	else
		function _G.ClangFormat()
			local cwd = vim.b.clang_format_root
			if not cwd then
				cwd = vim.fs.root(0, '.clang-format')
				vim.b.clang_format_root = cwd
			end
			local lines = vim.api.nvim_buf_get_lines(0, vim.v.lnum-1, vim.v.lnum-1+vim.v.count, true)
			local result = vim.system({ 'clang-format' }, {
				cwd = cwd,
				stdin = lines,
				stdout = true,
				stderr = true,
			}):wait()
			if result.code ~= 0 then
				vim.notify(result.stderr)
				return
			end
			assert (result.stdout)
			lines = vim.split(result.stdout, '\n', { plain = true })
			if #lines > 0 and lines[#lines] == '' then
				lines[#lines] = nil
			end
			vim.api.nvim_buf_set_lines(0, vim.v.lnum-1, vim.v.lnum-1+vim.v.count, true, lines)
		end
---@diagnostic disable-next-line: redefined-local
		M.try_enable_clang_format = function(bufnr)
			bufnr = bufnr or 0
			vim.bo[bufnr].formatexpr = 'v:lua.ClangFormat()'
			return true
		end
		return M.try_enable_clang_format(bufnr)
	end
end

return M
