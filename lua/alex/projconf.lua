local M = {}

---@diagnostic disable-next-line: undefined-field
local fs_stat = (vim.uv or vim.loop).fs_stat

---@param path string
---@return string
local function path_to_hash(path)
	local s, _ = path:gsub("#", "#h"):gsub("/", "#a"):gsub("\\", "#b")
	return s
end

---@param hash string
---@return string
local function hash_to_path(hash)
	local s, _ = hash:gsub("#a", "/"):gsub("#b", "\\"):gsub("#h", "#")
	return s
end

local state_dir = vim.fn.stdpath("state") .. "/projconf"

local function get_config_path(cwd)
	cwd = cwd or vim.fn.getcwd()
	local name = path_to_hash(cwd)
	return state_dir .. "/" .. name .. ".lua"
end

local loaded_configs = {}

local function load_config()
	loaded_configs = {}
	local jobs = {}
	vim.fn.mkdir(state_dir, "p")
	local cwd = vim.fn.getcwd()
	while true do
		local path = get_config_path(cwd)
		if fs_stat(path) then
			table.insert(loaded_configs, cwd)
			table.insert(jobs, vim.fn.fnameescape(path))
		end
		local nextcwd = cwd:match("^(.*)/")
		if not nextcwd then
			break
		end
		cwd = nextcwd
	end
	for i=#jobs,1,-1 do
		vim.cmd.luafile(jobs[i]) -- outer configs are loaded first
	end
end

local function edit_config()
	local path = get_config_path()
	vim.cmd.edit(vim.fn.fnameescape(path))
end

local function view_config()
	local path = get_config_path()
	vim.cmd.view(vim.fn.fnameescape(path))
end

local function delete_config()
	local path = get_config_path()
	vim.fs.rm(path, {
		force = true
	})
end

local function cleanup()
-- remove obselete configs
	for file, type in vim.fs.dir(state_dir) do
		if type == "file" then
			local name = file:match("^(.*)%.lua$")
			if name then
				local path = hash_to_path(name)
				if not fs_stat(path) then
					vim.fs.rm(state_dir .. "/" .. file)
				end
			end
		end
	end
end

local function print_loaded()
	for _, path in ipairs(loaded_configs) do
		print(path)
	end
end

M.load_config = load_config
M.edit_config = edit_config
M.view_config = view_config
M.delete_config = delete_config
M.path_to_hash = path_to_hash
M.hash_to_path = hash_to_path
M.print_loaded = print_loaded
M.cleanup = cleanup

function M.setup()
	vim.api.nvim_create_user_command("ProjConf", function(opts)
		local cmd = opts.fargs[1]
		local actions = {
			edit = edit_config,
			load = load_config,
			view = view_config,
			delete = delete_config,
			cleanup = cleanup,
			loaded = print_loaded,
		}
		local action = actions[cmd]
		if action then
			action()
		else
			vim.notify(("Invalid projconf command '%s'"):format(cmd), vim.log.levels.ERROR)
		end
	end, {
		nargs = 1,
		complete = function(arg, _, _)
			local pattern = "^" .. arg
			local entries = { "edit", "view", "load", "delete", "cleanup", "loaded" }
			return vim.tbl_filter(function(entry)
				return entry:match(pattern)
			end, entries)
		end,
	})
	if not os.getenv("PROJCONF_SUPPRESS") then
		load_config()
	end
end

return M
