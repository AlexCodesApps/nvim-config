local M = {}

---@class alex.ffind.WinState
---@field outer_window integer
---@field outer_winbuf integer
---@field inner_window integer
---@field inner_winbuf integer
---@field augroup integer
---@field lines string[]
---@field fzlines string[]
---@field sorter fun(lines: string[], input: string): string[]
---@field cursor integer
---@field schedule_id integer

local winstate = nil ---@type alex.ffind.WinState?

local function terminate_winstate()
	if winstate == nil then return end
	vim.api.nvim_del_augroup_by_id(winstate.augroup)
	vim.api.nvim_win_close(winstate.inner_window, true)
	vim.api.nvim_win_close(winstate.outer_window, true)
	vim.cmd.stopinsert()
	winstate = nil
end

---@return integer
local function get_max_lines()
	assert(winstate)
	return vim.api.nvim_win_get_height(winstate.outer_window)
end

---@return integer
local function get_line_count()
	assert(winstate)
	return vim.api.nvim_buf_line_count(winstate.outer_winbuf)
end

---@param lines string[]
local function set_winstate_lines(lines)
	assert(winstate)
	local outer_height = get_max_lines()
	local min = math.min(#lines, outer_height)
	local nlines = {}
	for i = #lines - (min - 1), #lines do
		table.insert(nlines, lines[i])
	end
	vim.api.nvim_buf_set_lines(
		winstate.outer_winbuf,
		0,
		-1,
		false,
		nlines
	)
end

---@param cwd string
---@param prefix? string
---@param exclude_pattern? string
---@return string[]
local function get_recursive_files(cwd, prefix, exclude_pattern)
	local function get_recursive_files_iter(files, path, prefixed_path, sep)
		for _, file in ipairs(vim.fn.readdir(path)) do
			if file == "." or file == ".." then
				goto next
			end
			if exclude_pattern and string.match(file, exclude_pattern) ~= nil then
				goto next
			end
			local npath = path .. "/" .. file
			if vim.fn.isdirectory(npath) ~= 0 then
				get_recursive_files_iter(files, npath, prefixed_path .. sep .. file, "/")
				goto next
			end
			table.insert(files, prefixed_path .. sep .. file)
			::next::
		end
		return files
	end
	local sep = ""
	if not prefix then
		prefix = cwd
		sep = "/"
	end
	return get_recursive_files_iter({}, cwd, prefix, sep)
end

---@param newpos integer
local function set_cursor(newpos)
	assert(winstate)
	winstate.cursor = newpos
	vim.api.nvim_win_set_cursor(winstate.outer_window, { get_line_count() - newpos, 1 })
end

local function reset_fzlines()
	assert(winstate)
	local input = vim.api.nvim_get_current_line()
	if input == "" then
		winstate.fzlines = winstate.lines
		return
	end
	set_cursor(0)
	local schedule_id = winstate.schedule_id
	winstate.schedule_id = winstate.schedule_id + 1
	vim.schedule(function()
		if not winstate then return end
		winstate.fzlines = vim.fn.reverse(winstate.sorter(winstate.lines, input))
		if schedule_id + 1 == winstate.schedule_id then -- to avoid time travelling
			set_winstate_lines(winstate.fzlines)
		end
	end)
end

local function move_cursor_up()
	assert(winstate)
	set_cursor(math.min(winstate.cursor + 1, get_line_count() - 1))
end

local function move_cursor_down()
	assert(winstate)
	set_cursor(math.max(winstate.cursor - 1, 0))
end

---@return string?
local function get_selected_field()
	assert(winstate)
	if #winstate.fzlines == 0 then
		return nil
	end
	return winstate.fzlines[#winstate.fzlines - winstate.cursor]
end

---@param lines string[]
---@param on_select fun(selected: string?, winmode: "none" | "vert" | "norm"): any
---@param sorter fun(lines: string[], input: string): string[]
local function open_picker(lines, on_select, sorter)
	terminate_winstate()
	local outer_winbuf = vim.api.nvim_create_buf(false, true)
	local inner_winbuf = vim.api.nvim_create_buf(false, true)
	local outer_window = vim.api.nvim_open_win(outer_winbuf, false, {
		relative = "editor",
		style = "minimal",
		border = "none",
		width = math.floor(vim.o.columns * 0.7),
		height = math.floor(vim.o.lines * 0.7),
		row = math.floor(vim.o.lines * 0.15),
		col = math.floor(vim.o.columns * 0.15),
	})
	local inner_window = vim.api.nvim_open_win(inner_winbuf, true,  {
		relative = "win",
		win = outer_window,
		style = "minimal",
		border = "none",
		width = vim.api.nvim_win_get_width(outer_window),
		height = 1,
		row = vim.api.nvim_win_get_height(outer_window),
		col = 0,
	})
	local augroup = vim.api.nvim_create_augroup("alex.ffind", {
		clear = true
	})
	vim.wo[outer_window].cursorline = true
	vim.wo.winhl = "Normal:Alex.FFind"
	vim.api.nvim_set_hl(0, "Alex.FFind", { bg = "#202040" })
	vim.api.nvim_create_autocmd("BufLeave", {
		group = augroup,
		buffer = inner_winbuf,
		callback = terminate_winstate,
	})
	vim.api.nvim_create_autocmd("WinLeave", {
		group = augroup,
		callback = terminate_winstate,
	})
	winstate = {
		outer_window = outer_window,
		outer_winbuf = outer_winbuf,
		inner_window = inner_window,
		inner_winbuf = inner_winbuf,
		augroup = augroup,
		lines = lines,
		fzlines = lines,
		sorter = sorter,
		cursor = 0,
		schedule_id = 0,
	}
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = augroup,
		buffer = inner_winbuf,
		callback = reset_fzlines,
	})
	vim.keymap.set("n", "<Esc>", terminate_winstate, { buffer = true })
	vim.keymap.set({ "n", "i" }, "<Enter>", function()
		local result = get_selected_field()
		terminate_winstate()
		on_select(result, "none")
	end, { buffer = true })
	vim.keymap.set({ "n", "i" }, "<C-v>", function()
		local result = get_selected_field()
		terminate_winstate()
		on_select(result, "vert")
	end, { buffer = true })
	vim.keymap.set({ "n", "i" }, "<C-n>", function()
		local result = get_selected_field()
		terminate_winstate()
		on_select(result, "norm")
	end, { buffer = true })
	vim.keymap.set("n", "k", move_cursor_up, { buffer = true })
	vim.keymap.set("n", "j", move_cursor_down, { buffer = true })
	vim.keymap.set("i", "<C-k>", move_cursor_up, { buffer = true })
	vim.keymap.set("i", "<C-j>", move_cursor_down, { buffer = true })
	set_winstate_lines(lines)
	set_cursor(0)
	vim.cmd.startinsert()
end

---@class alex.ffind.FindFileConfig
---@field cwd? string
---@field exclude_pattern? string

---@param config? alex.ffind.FindFileConfig
function M.find_file(config)
	local path = config and config.cwd or vim.fn.getcwd()
	local exclude_pattern = config and config.exclude_pattern
	local function on_select(line, winmode)
		if not line then return end
		local table = {
			none = "e ",
			norm = "new ",
			vert = "vnew ",
		}
		vim.cmd(table[winmode] .. path .. "/" .. line)
	end
	vim.schedule(function()
		open_picker(get_recursive_files(path, "", exclude_pattern), on_select, vim.fn.matchfuzzy)
	end)
end

return M
