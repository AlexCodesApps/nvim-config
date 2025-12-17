local M = {}

local blacklist = {}
local exttable = {}

---@param path string
---@return string?, string?
local function split_filepath(path)
	local name = vim.fs.basename(path)
	return name:match("([^%.]*)%.(.*)")
end

---@param path string
---@return string
local function realpath(path)
---@diagnostic disable-next-line: undefined-field
	return (vim.uv or vim.loop).fs_realpath(path)
end

function M.block_file(path)
	path = realpath(path)
	assert(path)
	table.insert(blacklist, path)
end

---@param pair string[]
function M.add_extension_pair(pair)
	local a = pair[1]
	local b = pair[2]
	if exttable[a] == nil then
		exttable[a] = {}
	end
	table.insert(exttable[a], b)
	if exttable[b] == nil then
		exttable[b] = {}
	end
	table.insert(exttable[b], a)
end

---@param pairs string[][]
function M.add_extension_pairs(pairs)
	for _, pair in ipairs(pairs) do
		M.add_extension_pair(pair)
	end
end

function M.cswitch()
	local path = vim.api.nvim_buf_get_name(0)
	local name, ext = split_filepath(path)
	if not name then
		vim.notify('No extension found')
		return
	end
	local extensions = exttable[ext]
	if extensions == nil then
		vim.notify('Unknown extension [.' .. ext .. ']')
		return
	end
	local files = vim.iter(extensions)
		:map(function(ext2)
			return vim.fn.findfile(name .. '.' .. ext2, '**', -1)
		end)
		:flatten()
		:map(realpath)
		:filter(function(file)
			return not vim.tbl_contains(blacklist, file)
		end)
		:totable()
	if #files == 0 then
		vim.notify('No candidates found')
		return
	end
	if #files ~= 1 then
		vim.notify('Multiple candidates found')
		vim.print(files)
		return
	end
	vim.cmd('e ' .. vim.fn.fnameescape(files[1]))
end

M.add_extension_pairs({
	{ 'c', 'h', },
	{ 'cc', 'hh' },
	{ 'cpp', 'hpp' },
	{ 'js', 'html' },
	{ 'ts', 'html' },
})

return M
