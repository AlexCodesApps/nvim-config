local M = {}

---@class alex.float.WinConfig
---@field enter? boolean
---@field width? number
---@field height? number

---creates a new floating window, hidden by default
---@param buffer integer
---@param opts alex.float.WinConfig
---@return integer
function M.open_floating_window(buffer, opts)
	local enter = opts.enter or true
	local winwidth = vim.o.columns
	local winheight = vim.o.lines
	local width = opts.width
		or math.floor(winwidth * 0.8)
	local height = opts.height
		or math.floor(winheight * 0.8)
	local col = math.floor((winwidth - width) / 2)
	local row = math.floor((winheight - height) / 2)
	return vim.api.nvim_open_win(buffer, enter, {
		relative = "editor",
		style = "minimal",
		border = "rounded",
		width = width,
		height = height,
		row = row,
		col = col,
	})
end

---@param winid integer
function M.hide_floating_window(winid)
	vim.api.nvim_win_hide(winid)
end

return M
