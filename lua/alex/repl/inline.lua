local M = {}
local async = require('alex.async')
local stdin_packet_actor = require('alex.repl.actor').stdin_packet_actor

---@return alex.async.Actor
local function vim_actor()
	return async.Actor.new(function(input)
		return vim.inspect(vim.fn.eval(input))
	end)
end

---@return alex.async.Actor
local function lua_actor()
	return async.Actor.new(function(input)
		local chunk, err = loadstring('return ' .. input)
		if not chunk then
			return err
		end
		local output = vim.inspect(chunk())
		return output
	end)
end

local python_repl_path =
	vim.fn.stdpath('config') .. '/lua/alex/repl/python-inline-repl.py'
local scheme_repl_path =
	vim.fn.stdpath('config') .. '/lua/alex/repl/scheme-inline-repl.scm'

---@return alex.async.Actor
local function python_actor()
	return stdin_packet_actor {'python', python_repl_path}
end

---@return alex.async.Actor
local function scheme_actor()
	return stdin_packet_actor {'scheme', '--script', scheme_repl_path}
end

local ft_table = {
	vim = vim_actor,
	lua = lua_actor,
	python = python_actor,
	scheme = scheme_actor,
}

local ns = vim.api.nvim_create_namespace('InlineEvalText')
local cache = {}

---@param line1 integer
---@param line2 integer
---@return alex.async.Future
function M.eval_range(line1, line2)
	local lines = vim.api.nvim_buf_get_lines(0, line1-1, line2, false)
	local function on_output(output)
		return async.Future.value(
			vim.split(output, '\n', { plain = true, trimempty = true }))
	end
	local repl = require('alex.repl').get_repl_for_buffer(0)
	if repl and repl.interface.eval then
		local input = table.concat(lines, '\n')
		return repl.interface.eval(input):bind(on_output)
	end
	local bufnr = vim.fn.bufnr()
	if not cache[bufnr] then
		local actor_factory = ft_table[vim.bo.filetype]
		if not actor_factory then
			vim.notify("can't find eval providor for " .. vim.bo.filetype)
			return async.Future.err()
		end
		cache[bufnr] = actor_factory()
		vim.api.nvim_create_autocmd('BufDelete', {
			buffer = bufnr,
			once = true,
			callback = function()
				cache[bufnr]:shutdown()
				cache[bufnr] = nil
			end
		})
	end
	---@type alex.async.Actor
	local actor = cache[bufnr]
	return actor:request(table.concat(lines, '\n'))
				:bind(on_output)
end

---@param line1 integer
---@param line2 integer
function M.inline_eval(line1, line2)
	vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
	M.eval_range(line1, line2):bind(function(text)
		if #text == 1 then
			vim.api.nvim_buf_set_extmark(0, ns, line2-1, 0, {
				virt_text = {{'# ', 'Conceal'}, {text[1], 'Conceal'}}
			})
		else
			text = vim.tbl_map(function(line)
				return {{'# ', 'Conceal'}, { line , 'Conceal' }}
			end, text)
			vim.api.nvim_buf_set_extmark(0, ns, line2-1, 0, {
				virt_lines = text
			})
		end
		vim.api.nvim_create_autocmd({'TextChanged', 'TextChangedI', 'InsertEnter'}, {
			buffer = 0,
			once = true,
			callback = function()
				vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
			end
		})
		return async.Future.value()
	end):report_err()
end

function M.eval_in_buffer(line1, line2)
	M.eval_range(line1, line2):listen(function(text)
		vim.cmd.new()
		vim.api.nvim_buf_set_lines(0, 0, -1, false, text)
	end)
end

function M.clear_cache()
	for _, entry in pairs(cache) do
		entry:shutdown()
	end
	cache = {}
	M.repl_cache = cache
end

M.repl_cache = cache
return M
