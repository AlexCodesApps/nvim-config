if 1 == vim.fn.executable 'hyprctl' then
	---@diagnostic disable-next-line: duplicate-set-field
	vim.notify = function(msg, level, _)
		level = level or vim.log.levels.OFF
		local table = {
			[vim.log.levels.WARN] = { icon = '0', color = 'rgb(FFFF00)' },
			[vim.log.levels.ERROR] = { icon = '3', color = 'rbg(FF0000)' },
		}
		local info = table[level] or {}
		local icon = info.icon or '1'
		local color = info.color or "rbg(0000FF)"
		vim.system {
			'hyprctl',
			'notify',
			icon,
			'3000',
			color,
			msg
		}
	end
end

---@class alex.Overrides.InputOpts
---@field prompt? string
---@field default? string
---@field completion? string
---@field cancelreturn? string
---@field highlight? function

---@param opts alex.Overrides.InputOpts
---@on_confirm function
---@diagnostic disable-next-line: duplicate-set-field
vim.ui.input = function(opts, on_confirm)
	local borders = {
		"┌",
		"─",
		"┐",
		"│",
		"┘",
		"─",
		"└",
		"│",
	}
	local prompt = opts.prompt or ""
	local default = opts.default or ""
	local completion = opts.completion
	local hightlight = opts.highlight
	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = 'laststatus',
		anchor = 'SW',
		style = 'minimal',
		border = borders,
		width = vim.o.columns,
		height = 1,
		row = 2,
		col = 0,
	})
	vim.wo[win].winhl = 'Normal:Normal,FloatBorder:Normal'
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { prompt .. default })
	local augroup = vim.api.nvim_create_augroup('AlexOverrideInput', {
		clear = true,
	})
	local function terminate()
		vim.api.nvim_del_augroup_by_id(augroup)
		vim.api.nvim_buf_delete(buf, { force = true })
		vim.cmd.stopinsert()
	end
	local prompt_len = prompt:len()
	local insert_keys = '<Esc>A'
	local insert_keycodes = vim.api.nvim_replace_termcodes(insert_keys, true, false, true)
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = augroup,
		buffer = buf,
		callback = function()
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			if #lines > 1 then
				terminate()
				vim.notify('new-lines here are unsupported!')
				return
			end
			local line = lines[1]
			if not line or not vim.startswith(line, prompt) then
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, { prompt })
				if vim.api.nvim_get_mode().mode:match('^i') then
					vim.api.nvim_feedkeys(insert_keycodes, 'n', false)
				else
					vim.cmd('normal $')
				end
			end
		end
	})
	vim.keymap.set({ 'i', 'n' }, '<Enter>', function()
		local line = vim.api.nvim_get_current_line()
		local input = line:sub(prompt_len + 1)
		terminate()
		on_confirm(input)
	end, { buffer = buf })
	vim.keymap.set('n', '<Esc>', terminate, { buffer = buf })
	vim.cmd('startinsert!')
end
