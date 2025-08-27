local M = {}

local term_state = {
	buf = nil,
	win = nil,
}

local float = require('alex.float')

function M.toggle()
	local termopen = true
	if not term_state.buf or not vim.api.nvim_buf_is_valid(term_state.buf) then
		term_state.buf = vim.api.nvim_create_buf(false, true)
		termopen = false
	end
	if term_state.win and vim.api.nvim_win_is_valid(term_state.win) then
		float.hide_floating_window(term_state.win)
	else
		term_state.win = float.open_floating_window(term_state.buf, {})
		if not termopen then
			vim.cmd.terminal()
		end
		vim.wo[term_state.win].winhl = 'Normal:Normal,FloatBorder:Normal'
		vim.cmd.startinsert()
	end
end

function M.setup()
	vim.api.nvim_create_user_command('FloaTerm', M.toggle, {})
end

return M
