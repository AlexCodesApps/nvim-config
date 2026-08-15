local M = {}

local state = {}

local uv = vim.uv or vim.loop

function M.home_dir()
	if not state.home then
		state.home = uv.os_homedir()
	end
	return state.home
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

---@alias alex.api.RangeType 'char'|'line'|'block'

---@alias alex.api.CompletionType 'ctrl_x' | 'generic'

---@class alex.api.VisualModeInfo
---@field major 'x'
---@field range alex.api.RangeType

---@class alex.api.NormalModeInfo
---@field major 'n'
---@field pending boolean
---@field range? alex.api.RangeType
---@field term boolean

---@class alex.api.SelectModeInfo
---@field major 's'
---@field range alex.api.RangeType
---@field ctrl_o boolean

---@class alex.api.InsertModeInfo
---@field major 'i'
---@field completion? alex.api.CompletionType
---@field ctrl_o boolean

---@class alex.api.ReplaceModeInfo
---@field major 'R'
---@field virtual boolean
---@field completion? alex.api.CompletionType
---@field ctrl_o boolean

---@class alex.api.CommandLineMode
---@field major 'c'
---@field overstrike boolean
---@field ex boolean

---@class alex.api.HitEnterPromptMode
---@field major 'r'
---@field prompt_type 'normal'|'more'|'query'

---@class alex.api.ShellMode
---@field major '!'

---@class alex.api.TerminalMode
---@field major 't'
---@field ctrl_o boolean

---@alias alex.api.ModeInfo alex.api.VisualModeInfo
--- 						| alex.api.NormalModeInfo
--- 						| alex.api.SelectModeInfo
--- 						| alex.api.InsertModeInfo
--- 						| alex.api.ReplaceModeInfo
--- 						| alex.api.CommandLineMode
--- 						| alex.api.HitEnterPromptMode
--- 						| alex.api.ShellMode
--- 						| alex.api.TerminalMode

---@return alex.api.ModeInfo
function M.mode_info()
	---@type table<string, alex.api.ModeInfo>
	local tbl = {
		n = { major = 'n', pending = false, term = false },
		no = { major = 'n', pending = true, term = false },
		nov = { major = 'n', pending = true, range = 'char', term = false },
		noV = { major = 'n', pending = true, range = 'line', term = false },
		['no\22'] = { major = 'n', pending = true, range = 'block', term = false },
		niI = { major = 'i', ctrl_o = true },
		niR = { major = 'R', virtual = false, ctrl_o = true },
		niV = { major = 'R', virtual = true, ctrl_o = true },
		nt = { major = 'n', pending = false, term = true },
		ntT = { major = 't', ctrl_o = true },
		v = { major = 'x', range = 'char' },
		vs = { major = 's', range = 'char', ctrl_o = true },
		V = { major = 'x', range = 'line' },
		Vs = { major = 's', range = 'line', ctrl_o = true },
		['\22'] = { major = 'x', range = 'block' },
		['\22s'] = { major = 's', range = 'block', ctrl_o = true },
		s = { major = 's', range = 'char', ctrl_o = false },
		S = { major = 's', range = 'line', ctrl_o = false },
		['\19'] = { major = 's', range = 'block', ctrl_o = false },
		i = { major = 'i', ctrl_o = false },
		ic = { major = 'i', completion = 'generic', ctrl_o = false },
		ix = { major = 'i', completion = 'ctrl_x', ctrl_o = false },
		R = { major = 'R', virtual = false, ctrl_o = false },
		Rc = { major = 'R', virtual = false, completion = 'generic', ctrl_o = false },
		Rx = { major = 'R', virtual = false, completion = 'ctrl_x', ctrl_o = false },
		Rv = { major = 'R', virtual = true, ctrl_o = false },
		Rvc = { major = 'R', virtual = true, completion = 'generic', ctrl_o = false },
		Rvx = { major = 'R', virtual = true, completion = 'ctrl_x', ctrl_o = false },
		c = { major = 'c', overstrike = false, ex = false },
		cr = { major = 'c', overstrike = true, ex = false },
		cv = { major = 'c', overstrike = false, ex = true },
		cvr = { major = 'c', overstrike = true, ex = true },
		r = { major = 'r', prompt_type = 'normal' },
		rm = { major = 'r', prompt_type = 'more' },
		['r?'] = { major = 'r', prompt_type = 'query' },
		['!'] = { major = '!' },
		t = { major = 't', ctrl_o = false },
	}
	return tbl[vim.fn.mode(1)] or error('update')
end

---@param mode alex.api.ModeInfo
function M.mode_info_is_visual(mode)
	return mode.major == 'x'
end

---@return string[]
function M.get_selection()
	return vim.fn.getregion(
		vim.fn.getpos('v'),
		vim.fn.getpos('.'), { type = vim.fn.mode() })
end

---@param buf integer?
function M.ensure_treesitter_parse(buf)
	vim.treesitter.get_parser(buf):parse()
end

---@param node TSNode
function M.goto_node(node)
	local row, col = node:start()
	vim.api.nvim_win_set_cursor(0, { row+1, col })
end

---@param buf integer
---@param node TSNode
---@return string[]
function M.get_node_text(buf, node)
	local srow, scol = node:start()
	local erow, ecol = node:end_()
	return vim.api.nvim_buf_get_text(
		buf,
		srow, scol,
		erow, ecol, {})
end

return M
