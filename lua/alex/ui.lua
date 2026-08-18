local M = {}

---@param enable? boolean
function M.enable_custom_status_line(enable)
	if enable == nil then enable = true end
	vim.schedule(require('alex.statusline').setup)
end

---@param enable? boolean
function M.enable_ui2(enable)
	if enable == nil then enable = true end
	require('vim._core.ui2').enable {
		enable = enable,
		msg = {
			targets = {
				[''] = 'msg',
				empty = 'cmd',
				bufwrite = 'msg',
				confirm = 'cmd',
				emsg = 'pager',
				echo = 'msg',
				echomsg = 'msg',
				echoerr = 'pager',
				completion = 'cmd',
				list_cmd = 'pager',
				lua_error = 'pager',
				lua_print = 'msg',
				progress = 'msg',
				rpc_error = 'pager',
				quickfix = 'msg',
				search_cmd = 'cmd',
				search_count = 'cmd',
				shell_cmd = 'pager',
				shell_err = 'pager',
				shell_out = 'pager',
				shell_ret = 'msg',
				undo = 'msg',
				verbose = 'pager',
				wildlist = 'cmd',
				wmsg = 'msg',
				typed_cmd = 'cmd',
			},
			cmd = {
				height = 0.5,
			},
			dialog = {
				height = 0.5,
			},
			msg = {
				height = 0.3,
				timeout = 2500,
			},
			pager = {
				height = 0.5,
			},
		},
	}
end

function M.truncate_cmdline()
	vim.o.cmdheight = 0
	vim.api.nvim_create_autocmd('CmdlineEnter', {
		callback = function()
			vim.o.laststatus = 0
		end,
	})
	vim.api.nvim_create_autocmd('CmdlineLeave', {
		callback = function()
			vim.o.laststatus = 2
		end,
	})
end

local function setup()
	M.enable_ui2()
	M.enable_custom_status_line()
	M.truncate_cmdline()
end

vim.schedule(setup)

return M
