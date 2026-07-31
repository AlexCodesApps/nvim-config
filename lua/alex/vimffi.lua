local M = {}
M.data = {}
local counter = 0

local function backing()
	return M.data
end

---@class alex.vimffi.Object
---@field private id string
---@field private valid boolean
M.Object = {}
M.Object.__index = M.Object
---@param val any
function M.Object.new(val)
	local id = type(val) .. tostring(counter)
	counter = counter + 1
	backing()[id] = val
	return setmetatable({
		id = id,
		valid = true
	}, M.Object)
end

function M.Object:del()
	backing()[self.id] = nil
	self.valid = false
end

function M.Object:get()
	assert(self.valid, 'must be registered object')
	return backing()[self.id]
end

function M.Object:vim_script_name()
	return ("v:lua.require'alex.vimffi'.data.%s"):format(self.id)
end

return M
