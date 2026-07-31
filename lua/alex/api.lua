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
		local clang_format = require('alex.vimffi').Object.new(function()
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
		end)
---@diagnostic disable-next-line: redefined-local
		M.try_enable_clang_format = function(bufnr)
			bufnr = bufnr or 0
			vim.bo[bufnr].formatexpr = clang_format:vim_script_name() .. '()'
			return true
		end
		return M.try_enable_clang_format(bufnr)
	end
end

return M
