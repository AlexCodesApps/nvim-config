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

---@param str string
---@param max integer
---@rreturn string, boolean
function M.truncate_str_by_cells(str, max)
	local width = vim.fn.strdisplaywidth(str)
	if width <= max then
		return str, false
	end
	local off = 0
	local len = str:len()
	local rem = max
	local output = M.StringBuilder.new(len)
	while off < len do
		 local c = vim.fn.strpart(str, off, 1, 1)
		 local dw = vim.fn.strdisplaywidth(c)
		 if rem - dw < 0 then
			 break
		 end
		 rem = rem - dw
		 off = off + c:len()
		 output:put(c)
	end
	return output:get(), true
end

---@param msg string
---@param history boolean
---@param opts vim.api.keyset.echo_opts
---@return string|integer
function M.nvim_echo_trunc(msg, history, opts)
	local trunc
	msg, trunc = M.truncate_str_by_cells(msg, vim.v.echospace - 3)
	if trunc then
		msg = msg .. '...'
	end
	return vim.api.nvim_echo({{ msg }}, history, opts)
end

---@param buf integer
---@param start integer
---@param end_ integer
---@param filter fun(input: string[]): string[]?
---@return boolean
function M.filter_range(buf, start, end_, filter)
	local input = vim.api.nvim_buf_get_lines(buf, start, end_, true)
	local output = filter(input)
	if not output then return false end
	vim.api.nvim_buf_set_lines(buf, start, end_, true, output)
	return true
end

---@param name string
---@param filter fun(input: string[]): string[]?
---@param opts vim.api.keyset.user_command
function M.create_filter_user_command(name, filter, opts)
	local function preview(ropts, _, preview_buf)
		local input = vim.api.nvim_buf_get_lines(0, ropts.line1 - 1, ropts.line2, true)
		local output = filter(input)
		if not output then return 0 end
		vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, output)
		return 2
	end
	opts = vim.tbl_deep_extend('error', {
		range = true,
		preview = preview
	}, opts)
	vim.api.nvim_create_user_command(name, function(ropts)
		M.filter_range(0, ropts.line1 - 1, ropts.line2, filter)
	end, opts)
end

---@param filter fun(input: string[]): string[]?
---@return alex.vimffi.Object
function M.create_filter_format_obj(filter)
	return require('alex.vimffi').Object.new(function()
		local start = vim.v.lnum-1
		local end_ = start+vim.v.count
		M.filter_range(0, start, end_, filter)
	end)

end

---@class alex.api.CreateExternalFormatFilterOpts
---@field cwd string|nil

---@param cmd string[]
---@param make_opts? fun(): alex.api.CreateExternalFormatFilterOpts
---@return fun(input: string[]): string[]?
function M.create_external_format_filter(cmd, make_opts)
	return function(input)
		local opts = vim.tbl_extend('error', make_opts and make_opts() or {}, {
			stdin = input,
			stdout = true,
			stderr = true
		})
		local completed = vim.system(cmd, opts):wait()
		if completed.code ~= 0 then
			vim.notify(completed.stderr)
			return
		end
		assert (completed.stdout)
		return vim.split(completed.stdout, '\n', { plain = true })
	end
end

---@type fun(input: string[]): string[]?
M.clang_format = M.create_external_format_filter({ 'clang-format' }, function()
	local cwd = vim.fs.root(0, '.clang-format')
	return { cwd = cwd }
end)

---@param bufnr? integer
---@return boolean
function M.try_enable_clang_format(bufnr)
	if vim.fn.executable('clang-format') ~= 1 then
		M.try_enable_clang_format = function() end
		return false
	else
		local clang_format = M.create_filter_format_obj(M.clang_format)
---@diagnostic disable-next-line: redefined-local
		M.try_enable_clang_format = function(bufnr)
			bufnr = bufnr or 0
			vim.bo[bufnr].formatexpr = clang_format:vim_script_call()
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

--- luajit extension
local string_buffer = require('string.buffer')

---@class alex.api.StringBuilder
---@field private inner string.buffer
M.StringBuilder = {}
M.StringBuilder.__index = M.StringBuilder

---@param cap? integer
---@return self
function M.StringBuilder.new(cap)
	return setmetatable({
		inner = string_buffer.new(cap or 0)
	}, M.StringBuilder)
end

---@param str string
---@return self
function M.StringBuilder.from_str(str)
	local builder = M.StringBuilder.new(str:len())
	builder.inner:put(str)
	return builder
end

---@param data string
function M.StringBuilder:put(data)
	self.inner:put(data)
end

---@param len? integer
---@param ... integer|nil
---@return string
function M.StringBuilder:get(len, ...)
	return self.inner:get(len, ...)
end

---@return string
function M.StringBuilder:__tostring()
	return self.inner:tostring()
end

---@return string
function M.StringBuilder:tostring()
	return self:__tostring()
end

function M.StringBuilder:len()
	local _, len = self.inner:ref()
	return len
end

return M
