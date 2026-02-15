local M = {}

local cache = {}
local stdlib = nil

---@param docpath string
---@return { name: string, category: string, file: string }[]
local function get_docs_at_docpath(docpath)
	local final_tbl = {}
	for file, type in vim.fs.dir(docpath) do
		if type ~= "directory" then
			goto continue
		end
		if file == "src" then
			goto continue
		end
		if file:match("%.") then
			goto continue
		end
		local all_path = vim.fs.joinpath(docpath, file, "all.html")
		if vim.fn.filereadable(all_path) == 0 then
			goto continue
		end
		local res = vim.system(
			{ "lynx", "-dump", "-width=1024", "-hiddenlinks=ignore", "--", all_path}):wait()
		assert(res.code)
		local lines = vim.iter(vim.gsplit(res.stdout, "\n"))
						:filter(function (str) return str ~= "" end)
						:totable()
		local p1 = "%* %[.+%](.+)$"
		local p2 = "%* %[(.+)%](.+)$"
		local i = 1
		while not lines[i]:match("^%[.*%]Crate Items$") do
			i = i + 1
		end
		i = i + 1 -- skip previous header
		local categories = {}
		local files = {}
		while true do
			local category = lines[i]:match(p1)
			if not category then break end
			i = i + 1
			categories[category] = {}
		end
		i = i + 1 -- skip 'List of all items'
		while lines[i] ~= "References" do
			local header = lines[i]
			i = i + 1
			while true do
				local idx, entry = lines[i]:match(p2)
				if not idx then break end
				i = i + 1
				idx = tonumber(idx)
				table.insert(categories[header], { idx = idx, entry = entry })
			end
		end
		i = i + 1 -- skip header
		while lines[i] do
			local line = lines[i]
			i = i + 1
			local idx, entry = line:match("%s*(%d+)%. file://(.+)$")
			idx = tonumber(idx)
			assert(idx)
			files[idx] = entry
		end
		for category, entries in pairs(categories) do
			for _, entry in pairs(entries) do
				table.insert(final_tbl, {
					category = category,
					name = file .. "::" .. entry.entry,
					file = files[entry.idx],
				})
			end
		end
	::continue::
	end
	return final_tbl
end

---@return { name: string, category: string, file: string }[]?
function M.get_stdlib_docs()
	if stdlib then return stdlib end
	local obj = vim.system({ "rustup", "doc", "--std", "--path" }):wait()
	if obj.code ~= 0 then
		vim.notify("Couldn't fetch stdlib path")
		return
	end
	local dir = vim.fs.dirname(vim.fs.dirname(obj.stdout))
	assert(dir)
	stdlib = get_docs_at_docpath(dir)
	return stdlib
end

---@param root? string
---@param update? boolean
---@return { name: string, category: string, file: string }[]?
function M.get_docs(root, update)
	update = update or true
	root = root or vim.fs.root(vim.env.PWD, "Cargo.toml")
	if not root then
		vim.notify("Couldn't find project root")
		return nil
	end
---@diagnostic disable-next-line: undefined-field
	root = (vim.uv or vim.loop).fs_realpath(root)
	assert(root)
	if cache[root] then
		return cache[root]
	end
	if update then
		local res = vim.system({"cargo", "doc"}, { cwd = root })
						:wait()
		if res.code ~= 0 then
			vim.notify("Couldn't update project documentation")
			print(res.stderr)
			return
		end
	end

	local docpath = vim.fs.joinpath(root, "target", "doc")
	local result = get_docs_at_docpath(docpath)
	local std = M.get_stdlib_docs()
	if not std then return end
	result = vim.list_extend(result, std)
	cache[root] = result
	return result
end

---@param file string
function M.open_file(file)
	if os.getenv("TMUX") then
		vim.fn.system({"tmux", "split-window", "lynx", "-vikeys", "--", file})
	else
		vim.cmd("vert term lynx -vikeys -- " .. vim.fn.fnameescape(file))
	end
end

return M
