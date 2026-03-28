local M = {}

local blacklist = {}
local exttable = {}
local filepairs = {}

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

function M.add_file_pair(a, b)
	a = realpath(a)
	b = realpath(b)
	filepairs[a] = b
	filepairs[b] = a
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
	local function on_select(file)
		if not file then return end
		vim.cmd('e ' .. vim.fn.fnameescape(file))
	end
	local path = vim.api.nvim_buf_get_name(0)
	path = realpath(path)
	if filepairs[path] ~= nil then
		on_select(filepairs[path])
		return
	end
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
	if #files == 1 then
		on_select(files[1])
	else
		vim.ui.select(files, { prompt = "Select Candidate File:" }, on_select)
	end
end

return M
