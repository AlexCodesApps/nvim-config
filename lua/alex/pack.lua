local config_path = vim.fn.stdpath('config')
local plugins_path = config_path .. '/lua/plugins/'
local repohost = 'https://www.github.com/'
local specs = {}

for name, ty in vim.fs.dir(plugins_path) do
	local no_ext = name:match('^(.*)%.lua$')
	if ty == 'file' and no_ext then
		local ret = dofile(plugins_path .. name)
		assert(type(ret) == 'table')
		local spec = { name = no_ext, data = {} }
		for key, value in pairs(ret) do
			if key == 1 then
				spec.src = repohost .. value
			elseif key == 'version' then
				if type(value) == 'string' then
					spec.version = vim.version.range(value)
				else
					spec.version = value
				end
			elseif key == 'name' then
				spec.name = value
			elseif key == 'dependencies' then
				vim.validate('dependencies', value, { 'table', 'string' })
				for _, short_src in ipairs(value) do
					local src = repohost .. short_src
					local isdup = vim.tbl_contains(specs, function(dup)
						if type(dup) == 'string' then
							return dup == src
						else
							return dup.src == src
						end
					end)
					if not isdup then
						specs[#specs + 1] = src
					end
				end
			else
				spec.data[key] = value
			end
		end
		for i, dup in ipairs(specs) do
			if type(dup) == 'string' and dup == spec.src then
				specs[i] = spec
				goto continue
			end
			if dup.name == spec.name or dup.src == spec.src then
				specs[i] = vim.tbl_deep_extend('error', dup, spec)
				goto continue
			end
		end
		specs[#specs+1] = spec
	::continue::
	end
end

-- setup plugins
vim.pack.add(specs)

local prio = {}
local norm = {}

for _, pack in ipairs(vim.pack.get()) do
	if pack.active then
		if pack.spec.data and pack.spec.data.priority then
			prio[#prio+1] = pack
		else
			norm[#norm+1] = pack
		end
	end
end

table.sort(prio, function(a, b)
	return a.spec.data.priority > b.spec.data.priority
end)

local function load_plugin(pack)
	local data = pack.spec.data
	local ok, plugin = pcall(require, pack.spec.name)
	if ok then
		if not data then
			if plugin.setup then
				pcall(plugin.setup)
			end
		elseif data.config == true then
			pcall(plugin.setup)
		elseif data.config then
			pcall(data.config)
		elseif data.opts then
			pcall(plugin.setup, data.opts)
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
