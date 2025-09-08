local M = {}

---@class alex.ffind.PickerEntry
---@field text string
---@field data any
M.picker_entry = {}

---@param text string
---@param data any
---@return alex.ffind.PickerEntry
function M.picker_entry.new(text, data)
	local obj = {
		text = text,
		data = data,
	}
	return obj
end

---@alias alex.ffind.WinMode "none"|"norm"|"vert"

---@param list string[]
---@return alex.ffind.PickerEntry[]
function M.picker_entry.from_list(list)
	local function helper(text)
		return M.picker_entry.new(text, nil)
	end
	return vim.tbl_map(helper, list)
end

---@class alex.ffind.WinState
---@field outer_window integer
---@field outer_winbuf integer
---@field inner_window integer
---@field inner_winbuf integer
---@field augroup integer
---@field lines alex.ffind.PickerEntry[]
---@field fzlines alex.ffind.PickerEntry[]
---@field screen_lines string[]
---@field screen_offset integer
---@field screen_cursor_offset integer
---@field cursor_offset integer
---@field sorter fun(lines: alex.ffind.PickerEntry[], input: string): alex.ffind.PickerEntry[]
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

---@return string[]
local function get_winstate_lines()
	assert(winstate)
	local lines = winstate.fzlines
	local outer_height = get_max_lines()
	local min = math.min(#lines, outer_height)
	local nlines = {} ---@type string[]
	for i = min, 1, -1 do
		table.insert(nlines, lines[i].text)
	end
	return nlines
end

local function print_winstate_lines()
	assert(winstate)
	vim.api.nvim_buf_set_lines(
		winstate.outer_winbuf,
		0,
		-1,
		false,
		winstate.screen_lines
	)
end

local function reset_winstate_lines()
	assert(winstate)
	winstate.screen_offset = 0
	winstate.cursor_offset = 0
	winstate.screen_cursor_offset = 0
	winstate.screen_lines = get_winstate_lines()
	print_winstate_lines()
end

---@param cwd string
---@param prefix? string
---@param exclude_pattern? string
---@param gitignore boolean
---@return string[]
local function get_recursive_files(cwd, prefix, exclude_pattern, gitignore)
	local re = exclude_pattern and vim.regex(exclude_pattern)
	local gi = gitignore and M.gitignore.from_cwd(cwd)
	local function get_recursive_files_iter(files, path, prefixed_path, sep, fst)
		for _, file in ipairs(vim.fn.readdir(path)) do
			if file == "." or file == ".." then
				goto next
			end
			if re and re:match_str(file) then
				goto next
			end
			if gi and not gi:allow(file) then
				goto next
			end
			local npath = path .. "/" .. file
			if vim.fn.isdirectory(npath) ~= 0 then
				get_recursive_files_iter(files, npath, prefixed_path .. sep .. file, "/", false)
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
	return get_recursive_files_iter({}, cwd, prefix, sep, true)
end

local function screen_cursor_offset_check(offset)
	assert(winstate)
	local max = get_line_count()
	local index = max - offset
	if index > max or index < 1 then
		return nil
	end
	return index
end

local scroll_screen_up
local scroll_screen_down

local function print_screen_cursor()
	assert(winstate)
	local index = screen_cursor_offset_check(winstate.screen_cursor_offset)
	assert(index)
	vim.api.nvim_win_set_cursor(winstate.outer_window, { index, 0 })
end

local function reset_fzlines()
	assert(winstate)
	local input = vim.api.nvim_get_current_line()
	if input == "" then
		winstate.fzlines = winstate.lines
		reset_winstate_lines()
		print_screen_cursor()
		return
	end
	local schedule_id = winstate.schedule_id
	winstate.schedule_id = winstate.schedule_id + 1
	vim.schedule(function()
		if not winstate then return end
		local fzlines = winstate.sorter(winstate.lines, input)
		if schedule_id + 1 == winstate.schedule_id then -- to avoid time travelling
			winstate.fzlines = fzlines
			reset_winstate_lines()
			print_screen_cursor()
		end
	end)
end

local function move_cursor_up()
	assert(winstate)
	if winstate.cursor_offset + 1 == #winstate.fzlines then return end
	if screen_cursor_offset_check(winstate.screen_cursor_offset + 1) then
		winstate.cursor_offset = winstate.cursor_offset + 1
		winstate.screen_cursor_offset = winstate.screen_cursor_offset + 1
	else
		scroll_screen_up(true)
	end
	print_screen_cursor()
end

local function move_cursor_down()
	assert(winstate)
	if winstate.cursor_offset == 0 then return end
	if screen_cursor_offset_check(winstate.screen_cursor_offset - 1) then
		winstate.cursor_offset = winstate.cursor_offset + 1
		winstate.screen_cursor_offset = winstate.screen_cursor_offset - 1
	else
		scroll_screen_down(true)
	end
	print_screen_cursor()
end

---@param move_cursor? boolean
scroll_screen_up = function(move_cursor)
	assert(winstate)
	if #winstate.screen_lines + winstate.screen_offset + 1 >= #winstate.fzlines then
		return
	end
	winstate.screen_offset = winstate.screen_offset + 1
	local new_line = winstate.fzlines[winstate.screen_offset + #winstate.screen_lines].text
	table.remove(winstate.screen_lines, #winstate.screen_lines)
	table.insert(winstate.screen_lines, 1, new_line)
	print_winstate_lines()
	if not move_cursor then
		if screen_cursor_offset_check(winstate.screen_cursor_offset - 1) then
			winstate.screen_cursor_offset = winstate.screen_cursor_offset - 1
		else
			winstate.cursor_offset = winstate.cursor_offset + 1
		end
		print_screen_cursor()
	else
		winstate.cursor_offset = winstate.cursor_offset + 1
	end
end

---@param move_cursor? boolean
scroll_screen_down = function(move_cursor)
	assert(winstate)
	if winstate.screen_offset <= 0 then
		return
	end
	winstate.screen_offset = winstate.screen_offset - 1
	local new_line = winstate.fzlines[winstate.screen_offset + 1].text
	table.remove(winstate.screen_lines, 1)
	table.insert(winstate.screen_lines, new_line)
	print_winstate_lines()
	if not move_cursor then
		if screen_cursor_offset_check(winstate.screen_cursor_offset + 1) then
			winstate.screen_cursor_offset = winstate.screen_cursor_offset + 1
		else
			winstate.cursor_offset = winstate.cursor_offset - 1
		end
		print_screen_cursor()
	else
		winstate.cursor_offset = winstate.cursor_offset - 1
	end
end

---@return alex.ffind.PickerEntry?
local function get_selected_field()
	assert(winstate)
	if #winstate.fzlines == 0 then
		return nil
	end
	return winstate.fzlines[1 + winstate.cursor_offset]
end

---@param lines alex.ffind.PickerEntry[]
---@param on_select fun(selected: alex.ffind.PickerEntry?, winmode: alex.ffind.WinMode): any
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
		screen_lines = {},
		screen_offset = 0,
		sorter = sorter,
		cursor_offset = 0,
		screen_cursor_offset = 0,
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
	vim.keymap.set({"n", "i"}, "<C-y>", scroll_screen_up, { buffer = true })
	vim.keymap.set({"n", "i"}, "<C-e>", scroll_screen_down, { buffer = true })
	reset_winstate_lines()
	print_screen_cursor()
	vim.cmd.startinsert()
end

---@param entries alex.ffind.PickerEntry[]
---@param input string
---@return alex.ffind.PickerEntry[]
function M.default_sorter(entries, input)
	return vim.fn.matchfuzzy(entries, input,  {
		key = "text"
	})
end

---@class alex.ffind.GitIgnoreRule
---@field allow boolean
---@field pattern vim.lpeg.Pattern

---@class alex.ffind.GitIgnore
---@field rules alex.ffind.GitIgnoreRule[]
M.gitignore = {}

---@param src string[]
---@return alex.ffind.GitIgnore
function M.gitignore.parse(src)
	local rules = {}
	local function convert(allow, str)
		return { allow = allow, pattern = vim.glob.to_lpeg(str) } ---@type alex.ffind.GitIgnoreRule
	end
	for _, line in ipairs(src) do
		if line == "" then goto continue end
		local c1 = line:sub(1, 1)
		if c1 == "#" then
			goto continue
		elseif c1 == "!" then
			table.insert(rules, convert(true, string.sub(line, 2)))
		elseif c1 == "\\" then
			 table.insert(rules, convert(false, string.sub(line, 2)))
		else
			table.insert(rules, convert(false, line))
		end
		::continue::
	end
	local obj = {
		rules = rules
	}
	setmetatable(obj, M.gitignore)
	return obj
end

---@param cwd? string
---@return alex.ffind.GitIgnore?
function M.gitignore.from_cwd(cwd)
	cwd = cwd or vim.fn.getcwd()
	local ok, lines = pcall(vim.fn.readfile, cwd .. "/.gitignore")
	if not ok then
		return nil
	end
	return M.gitignore.parse(lines)
end

---@param path string
---@return boolean
function M.gitignore:allow(path)
	local allow = true
	if path == ".git" or string.match(path, "^%.git/") then
		return false
	end
	for _, rule in ipairs(self.rules) do
		if rule.pattern:match(path) then
			allow = rule.allow
		end
	end
	return allow
end

M.gitignore.__index = M.gitignore

---@class alex.ffind.FindFileConfig
---@field cwd? string
---@field exclude_pattern? string
---@field gitignore? boolean

---@param config? alex.ffind.FindFileConfig
function M.find_file(config)
	config = config or {}
	local path = config.cwd or vim.fn.getcwd()
	local exclude_pattern = config.exclude_pattern
	local gitignore = config.gitignore or false
	---@param entry alex.ffind.PickerEntry?
	---@param winmode alex.ffind.WinMode
	local function on_select(entry, winmode)
		if not entry then return end
		local line = entry.text
		local table = {
			none = "e ",
			norm = "new ",
			vert = "vnew ",
		}
		vim.cmd(table[winmode] .. path .. "/" .. line)
	end
		local files = get_recursive_files(path, "", exclude_pattern, gitignore)
		local entries = M.picker_entry.from_list(files)
		open_picker(entries, on_select, M.default_sorter)
end

---@class alex.ffind.GrepFilesConfig
---@field cwd? string
---@field exclude_pattern? string
---@field gitignore? boolean

---@param config? alex.ffind.GrepFilesConfig
function M.grep_files(config)
	config = config or {}
	local cwd = config.cwd or vim.fn.getcwd()
	local gitignore = config.gitignore or false
	local files = get_recursive_files(cwd, "", config.exclude_pattern, gitignore)
	---@param _ alex.ffind.PickerEntry
	---@param input string
	---@return alex.ffind.PickerEntry[]
	local function sorter(_, input)
		local cmd = { "xargs", "grep", "-nE", input };
		local result = vim.system(cmd, {
			text = true,
			stdin = files,
			-- timeout = 2000 -- needed to make large directory greps not break everything
						  -- esp when the user only output something like 'a'
						  -- currently gets hung up on '.bash_history' on my system apparently
		}):wait()
		local lines = vim.fn.split(result.stdout, "\n")
		local entries = {}
		for _, line in ipairs(lines) do
			local file, row = string.match(line, "^([^:]+):(%d+):")
			if file then
				local entry = M.picker_entry.new(line, { file = file, row = tonumber(row) })
				table.insert(entries, entry)
			end
		end
		return entries
	end
	---@param entry alex.ffind.PickerEntry?
	---@param winmode alex.ffind.WinMode
	local function on_select(entry, winmode)
		if not entry then return end
		local file = entry.data.file
		local table = {
			none = "e ",
			norm = "new ",
			vert = "vnew ",
		}
		vim.cmd(table[winmode] .. file)
		local row = entry.data.row
		vim.api.nvim_win_set_cursor(0, {row, 0})
	end
	open_picker({}, on_select, sorter)
end

local cached_help_entries = nil ---@type alex.ffind.PickerEntry[]

function M.find_help()
	if not cached_help_entries then
		local rtp = vim.o.runtimepath
		cached_help_entries = {}
		for _, path in ipairs(vim.fn.globpath(rtp, "**/doc/tags", false, true)) do
			for _, line in ipairs(vim.fn.readfile(path)) do
				local entry = string.match(line, "^([^%s]+)%s")
				if not entry then goto continue end
				table.insert(cached_help_entries, M.picker_entry.new(entry, nil))
				::continue::
			end
		end
	end
	---@param entry alex.ffind.PickerEntry
	---@param winmode alex.ffind.WinMode
	local function on_select(entry, winmode)
		if not entry then return end
		local table = {
			none = "",
			norm = "",
			vert = "vert ",
		}
		local help = entry.text
		vim.cmd(table[winmode] .. "help " .. help)
	end
	open_picker(cached_help_entries, on_select, M.default_sorter)
end

return M
