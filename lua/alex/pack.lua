require('alex.remap')

local config_path = vim.fn.stdpath('config')
local plugins_path = config_path .. '/lua/plugins/'
local specs = {}

for name, ty in vim.fs.dir(plugins_path) do
	local no_ext = name:match('^(.*)%.lua$')
	if ty == 'file' and no_ext then
		local ret = dofile(plugins_path .. name)
		assert(type(ret) == 'table')
		local spec = { name = no_ext, data = {} }
		for key, value in pairs(ret) do
			if key == 1 then
				spec.src = 'https://www.github.com/' .. value
			elseif key == 'version' then
				spec.version = value
			elseif key == 'name' then
				spec.name = value
			else
				spec.data[key] = value
			end
		end
		specs[#specs+1] = spec
	end
end

-- setup plugins
vim.pack.add(specs)

local prio = {}
local norm = {}

for _, pack in ipairs(vim.pack.get()) do
	if pack.spec.data.priority then
		prio[#prio+1] = pack
	else
		norm[#norm+1] = pack
	end
end

table.sort(prio, function(a, b)
	return a.spec.data.priority > b.spec.data.priority
end)

local function load_plugin(pack)
	local data = pack.spec.data
	local ok, plugin = pcall(require, pack.spec.name)
	if ok then
		if data.config == true then
			plugin.setup()
		elseif data.config then
			data.config()
		elseif data.opts then
			plugin.setup(data.opts)
		end
	else
		vim.notify('Failed to locate plugin ' .. pack.spec.name)
	end
end

for _, pack in ipairs(prio) do
	load_plugin(pack)
end

for _, pack in ipairs(norm) do
	load_plugin(pack)
end
