local M = {}

local state = {}

local uv = vim.uv or vim.loop or {}

function M.home_dir()
	if not state.home then
---@diagnostic disable-next-line: undefined-field
		state.home = uv.os_homedir()
	end
	return state.home
end

---@param filename string
---@param mode? "none"|"norm"|"vert"
function M.edit_file(filename, mode)
	mode = mode or "none"
	local tbl = {
		none = "edit ",
		norm = "new ",
		vert = "vnew "
	}
	local cmd = tbl[mode] .. vim.fn.fnameescape(filename)
	vim.cmd(cmd)
end

return M
