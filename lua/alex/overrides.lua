local ffind = require('alex.ffind')

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

local terminate = nil

---@param opts alex.Overrides.InputOpts
---@param on_confirm function
---@diagnostic disable-next-line: duplicate-set-field
vim.ui.input = function(opts, on_confirm)
	if terminate then
		terminate()
	end
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
	-- local completion = opts.completion -- TODO: should do something
	-- local hightlight = opts.highlight
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
	terminate = function()
		vim.api.nvim_del_augroup_by_id(augroup)
		vim.api.nvim_buf_delete(buf, { force = true })
		vim.cmd.stopinsert()
		terminate = nil
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

---@class alex.Overrides.SelectOpts
---@field prompt? string
---@field format_item function
---@field kind? string

---@generic T
---@param items T[]
---@param opts alex.Overrides.SelectOpts
---@param on_choice fun(item: T|nil, idx: integer|nil)
---@diagnostic disable-next-line: duplicate-set-field
vim.ui.select = function(items, opts, on_choice)
	opts = opts or {}
	local prompt = opts.prompt or "Select one of:"
	local format_item = opts.format_item or tostring
	local entries = vim.tbl_map(function(item)
		return ffind.picker_entry.new(format_item(item), item)
	end, items)
	ffind.open_picker(entries, {
		title = prompt,
		actions = {
			on_select = function(entry, _)
				local idx = nil
				if entry ~= nil then
					for i, other in ipairs(entries) do
						if other == entry then
							idx = i
							break
						end
					end
				end
				on_choice(entry and entry.data, idx)
			end,
			on_cancel = function(selected)
				if not selected then
					on_choice(nil, nil)
				end
			end
		},
	})
end
