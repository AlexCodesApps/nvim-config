--[[
--	This module uses a simple bespoke binary format for transmitting messages,
--	[8byte big endian length][content].
]]--
local M = {}
local async = require('alex.async')

---@param i integer
---@return string
local function int_to_be64(i)
	local tbl = {}
	for s=1,4 do
		local shift = (4 - s) * 8
		local mask = bit.lshift(0xFF, shift)
		local bits = bit.band(i, mask)
		bits = bit.rshift(bits, shift)
		tbl[#tbl + 1] = bits
	end
	return string.char(0, 0, 0, 0, unpack(tbl))
end

---@param s string
---@return integer
local function be64_to_int(s)
	local a, b, c, d, e, f, g, h = s:byte(1, 8)
	assert(bit.bor(a, b) == 0)
	return    bit.lshift(c, 40)
			+ bit.lshift(d, 32)
			+ bit.lshift(e, 24)
			+ bit.lshift(f, 16)
			+ bit.lshift(g, 8)
			+ h
end

---@param args string[]
---@return alex.async.Actor
function M.server_actor(args)
	local queue = async.Mpsc.new()
	local proc, on_exit = async.vim.system(args, {
		stdin = true,
		stdout = function (err, data)
			if data then
				queue:push({ true, data })
			elseif err then
				queue:push({ false, err })
			else
				queue:shutdown()
			end
		end,
		stderr = function (err, data)
			if not data and not err then
				return
			end
			vim.notify('STDERR: ' .. data or err)
		end
	})
	local reader = async.stream.StreamReader.new(queue)
	local actor = async.Actor.new(function(input)
		assert(type(input) == 'string')
		local header = int_to_be64(input:len())
		proc:write(header)
		proc:write(input)
		local rheader = reader:read(8):await()
		if rheader:len() ~= 8 then
			error(('error reading header : expected 8 bytes, got %d bytes')
					:format(rheader:len()))
		end
		local len = be64_to_int(rheader)
		assert(len >= 0 and len < 4 * 1024 * 1024, 'not doing alat')
		local payload = reader:read(len):await()
		if payload:len() ~= len then
			error(('error reading payload : expected %d bytes, got %d bytes')
					:format(len, payload:len()))
		end
		return payload
	end)
	on_exit:sequence(function()
		actor:shutdown()
	end)
	actor:wait():sequence(function()
		proc:kill('sigterm')
	end)
	return actor
end

return M
