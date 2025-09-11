local M = {}

---@class alex.ffind.PickerEntry
---@field text string
---@field data any
M.picker_entry = {}

---@alias alex.ffind.SortFn fun(
	--- entries: alex.ffind.PickerEntry[], -- The entries to be sorted
	--- input: string, -- The current user input
	--- callback: fun(lines: alex.ffind.PickerEntry[])) -- Callback to be run, allowing asynchronous execution

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

---@class alex.ffind.Picker
---@field outer_window integer -- The window for displaying matches
---@field outer_winbuf integer -- The buffer for displaying matches
---@field inner_window integer -- The window for user input
---@field inner_winbuf integer -- The buffer for user input
---@field augroup integer -- The augroup for autocmds run in the picker
---						  -- This group is deleted on picker closing
---@field lines alex.ffind.PickerEntry[]
---@field fzlines alex.ffind.PickerEntry[]
---@field screen_lines string[]
---@field screen_offset integer
---@field screen_cursor_offset integer
---@field sorter alex.ffind.SortFn
---@field on_cancel? fun(selected: boolean)
---@field schedule_id integer

local g_picker = nil ---@type alex.ffind.Picker?

---@param selected? boolean
local function terminate_picker(selected)
	if g_picker == nil then return end
	vim.api.nvim_del_augroup_by_id(g_picker.augroup)
	vim.api.nvim_win_close(g_picker.inner_window, true)
	vim.api.nvim_win_close(g_picker.outer_window, true)
	vim.cmd.stopinsert()
	local on_cancel = g_picker.on_cancel
	g_picker = nil
	if on_cancel then on_cancel(selected or false) end
end

local function get_cursor_offset()
	assert(g_picker)
	return g_picker.screen_offset + g_picker.screen_cursor_offset
end

---@return integer
local function get_max_lines()
	assert(g_picker)
	return vim.api.nvim_win_get_height(g_picker.outer_window)
end

---@return integer
local function get_line_count()
	assert(g_picker)
	return vim.api.nvim_buf_line_count(g_picker.outer_winbuf)
end

---@return string[]
local function get_picker_lines()
	assert(g_picker)
	local lines = g_picker.fzlines
	local outer_height = get_max_lines()
	local min = math.min(#lines, outer_height)
	local nlines = {} ---@type string[]
	for i = min, 1, -1 do
		table.insert(nlines, lines[i].text)
	end
	return nlines
end

local function print_picker_lines()
	assert(g_picker)
	vim.api.nvim_buf_set_lines(
		g_picker.outer_winbuf,
		0,
		-1,
		false,
		g_picker.screen_lines
	)
end

local function reset_picker_lines()
	assert(g_picker)
	g_picker.screen_offset = 0
	g_picker.screen_cursor_offset = 0
	g_picker.screen_lines = get_picker_lines()
	print_picker_lines()
end

---@param cwd string
---@param prefix? string
---@param exclude_pattern? string
---@param gitignore boolean
---@param callback fun(files: string[])
local function fetch_recursive_files(cwd, prefix, exclude_pattern, gitignore, callback)
	prefix = prefix or ""
	local cmd
	if gitignore then
		cmd = { "rg", "--files" }
	else
		cmd = { "rg", "--no-ignore", "--files" }
	end
	vim.system(cmd, {
		cwd = cwd,
	}, function(result)
		local output = result.stdout
		assert(output)
		local files = {}
		for line in vim.gsplit(output, "\n") do
			if line ~= "" and (not exclude_pattern or line:match(exclude_pattern)) then
				table.insert(files, prefix .. line)
			end
		end
		vim.schedule(function() callback(files) end)
	end)
end

local function screen_cursor_offset_check(offset)
	assert(g_picker)
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
	assert(g_picker)
	local index = screen_cursor_offset_check(g_picker.screen_cursor_offset)
	assert(index)
	vim.api.nvim_win_set_cursor(g_picker.outer_window, { index, 0 })
end

--- Run on user input change
local function reset_fzlines()
	assert(g_picker)
	local input = vim.api.nvim_get_current_line()
	if input == "" then
		g_picker.fzlines = g_picker.lines
		reset_picker_lines()
		print_screen_cursor()
		return
	end
	local schedule_id = g_picker.schedule_id
	g_picker.schedule_id = g_picker.schedule_id + 1
	g_picker.sorter(g_picker.lines, input, function(fzlines)
		if not g_picker then return end
		if schedule_id + 1 == g_picker.schedule_id then -- to avoid time travelling
			g_picker.fzlines = fzlines
			reset_picker_lines()
			print_screen_cursor()
		end
	end)
end

local function move_cursor_up()
	assert(g_picker)
	if get_cursor_offset() + 1 == #g_picker.fzlines then return end
	if screen_cursor_offset_check(g_picker.screen_cursor_offset + 1) then
		g_picker.screen_cursor_offset = g_picker.screen_cursor_offset + 1
	else
		scroll_screen_up(true)
	end
	print_screen_cursor()
end

local function move_cursor_down()
	assert(g_picker)
	if get_cursor_offset() == 0 then return end
	if screen_cursor_offset_check(g_picker.screen_cursor_offset - 1) then
		g_picker.screen_cursor_offset = g_picker.screen_cursor_offset - 1
	else
		scroll_screen_down(true)
	end
	print_screen_cursor()
end

---@param move_cursor? boolean
scroll_screen_up = function(move_cursor)
	assert(g_picker)
	if #g_picker.screen_lines + g_picker.screen_offset + 1 >= #g_picker.fzlines then
		return
	end
	g_picker.screen_offset = g_picker.screen_offset + 1
	local new_line = g_picker.fzlines[g_picker.screen_offset + #g_picker.screen_lines].text
	table.remove(g_picker.screen_lines, #g_picker.screen_lines)
	table.insert(g_picker.screen_lines, 1, new_line)
	print_picker_lines()
	if not move_cursor then
		if screen_cursor_offset_check(g_picker.screen_cursor_offset - 1) then
			g_picker.screen_cursor_offset = g_picker.screen_cursor_offset - 1
		end
		print_screen_cursor()
	end
end

---@param move_cursor? boolean
scroll_screen_down = function(move_cursor)
	assert(g_picker)
	if g_picker.screen_offset <= 0 then
		return
	end
	g_picker.screen_offset = g_picker.screen_offset - 1
	local new_line = g_picker.fzlines[g_picker.screen_offset + 1].text
	table.remove(g_picker.screen_lines, 1)
	table.insert(g_picker.screen_lines, new_line)
	print_picker_lines()
	if not move_cursor then
		if screen_cursor_offset_check(g_picker.screen_cursor_offset + 1) then
			g_picker.screen_cursor_offset = g_picker.screen_cursor_offset + 1
		end
		print_screen_cursor()
	end
end

---@return alex.ffind.PickerEntry?
local function get_selected_field()
	assert(g_picker)
	if #g_picker.fzlines == 0 then
		return nil
	end
	return g_picker.fzlines[1 + get_cursor_offset()]
end

---@class alex.ffind.OpenPickerConfig
---@field on_select fun(selected: alex.ffind.PickerEntry?, winmode: alex.ffind.WinMode): any
---@field sorter? fun(lines: string[], input: string): string[]
---@field on_cancel? fun(selected: boolean)

---@param lines alex.ffind.PickerEntry[]
---@param config alex.ffind.OpenPickerConfig
function M.open_picker(lines, config)
	local on_select = config.on_select
	local sorter = config.sorter or M.default_sorter
	local on_cancel = config.on_cancel
	terminate_picker()
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
		callback = terminate_picker,
	})
	vim.api.nvim_create_autocmd("WinLeave", {
		group = augroup,
		callback = terminate_picker,
	})
	g_picker = {
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
		on_cancel = on_cancel,
		screen_cursor_offset = 0,
		schedule_id = 0,
	}
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = augroup,
		buffer = inner_winbuf,
		callback = reset_fzlines,
	})
	vim.keymap.set("n", "<Esc>", terminate_picker, { buffer = true })
	vim.keymap.set({ "n", "i" }, "<Enter>", function()
		local result = get_selected_field()
		terminate_picker(true)
		on_select(result, "none")
	end, { buffer = true })
	vim.keymap.set({ "n", "i" }, "<C-v>", function()
		local result = get_selected_field()
		terminate_picker(true)
		on_select(result, "vert")
	end, { buffer = true })
	vim.keymap.set({ "n", "i" }, "<C-n>", function()
		local result = get_selected_field()
		terminate_picker(true)
		on_select(result, "norm")
	end, { buffer = true })
	vim.keymap.set("n", "k", move_cursor_up, { buffer = true })
	vim.keymap.set("n", "j", move_cursor_down, { buffer = true })
	vim.keymap.set("i", "<C-k>", move_cursor_up, { buffer = true })
	vim.keymap.set("i", "<C-j>", move_cursor_down, { buffer = true })
	vim.keymap.set({"n", "i"}, "<C-y>", scroll_screen_up, { buffer = true })
	vim.keymap.set({"n", "i"}, "<C-e>", scroll_screen_down, { buffer = true })
	reset_picker_lines()
	print_screen_cursor()
	vim.cmd.startinsert()
end

---@type alex.ffind.SortFn
function M.default_sorter(entries, input, callback)
	callback(vim.fn.matchfuzzy(entries, input, {
		key = "text",
	}))
end

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
	fetch_recursive_files(path, "", exclude_pattern, gitignore, function(files)
		local entries = M.picker_entry.from_list(files)
		M.open_picker(entries, {
			on_select = on_select
		})
	end)
end

---@class alex.ffind.GrepFilesConfig
---@field cwd? string
---@field exclude_pattern? string
---@field gitignore? boolean

---@param config? alex.ffind.GrepFilesConfig
function M.grep_files(config)
	-- There is alot of machinery here to avoid
	-- Freezing Neovim on a large directory grep
	config = config or {}
	local cwd = config.cwd or vim.fn.getcwd()
	local gitignore = config.gitignore or false
	---@type vim.SystemObj?
	local running_future = nil
	---@type alex.ffind.SortFn
	local function sorter(_, input, callback)
		if running_future then
			running_future:kill("TERM")
			running_future = nil
		end
		local cmd
		if gitignore then
			cmd = { "rg", "-n", "--no-heading", input };
		else
			cmd = { "rg", "-n", "--no-heading", "--no-ignore", input }
		end
		running_future = vim.system(cmd, { cwd = cwd, text = true }, function(result)
			if result.code ~= 0 then return end
			local lines_iter = vim.gsplit(result.stdout, "\n")
			local entries = {}
			for line in lines_iter do
				local file, row = string.match(line, "^([^:]+):(%d+):")
				if file then
					local entry = M.picker_entry.new(line, { file = file, row = tonumber(row) })
					table.insert(entries, entry)
				end
			end
			-- can't call directly in fast mode
			vim.schedule(function() callback(entries) end)
		end)
	end
	local function on_cancel(_)
		if running_future then
			running_future:kill("TERM")
		end
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
	M.open_picker({}, {
		on_select = on_select,
		sorter = sorter,
		on_cancel = on_cancel,
	})
end

local cached_help_entries = nil ---@type alex.ffind.PickerEntry[]

function M.find_help()
	if not cached_help_entries then
		local rtp = vim.o.runtimepath
		cached_help_entries = {}
		for _, path in ipairs(vim.fn.globpath(rtp, "**/doc/tags", false, true)) do
			for _, line in ipairs(vim.fn.readfile(path)) do
				local entry = string.match(line, "^([^%s]+)%s")
				if entry then
					table.insert(cached_help_entries, M.picker_entry.new(entry, nil))
				end
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
	M.open_picker(cached_help_entries, {
		on_select = on_select,
	})
end

---@class alex.ffind.QfSymbolEntry
---@field col integer
---@field end_col integer
---@field end_lnum integer
---@field filename string
---@field kind string
---@field lnum integer
---@field text string

---@param list vim.lsp.LocationOpts.OnList
local function open_picker_qf_symbol_list(list)
	local items = list.items
	local entries = {}
	local white_list = {
		"Function",
		"Class",
		"Method",
		"Interface",
		"Enum",
		"Constructor",
		"EnumMember",
		"Field",
		"Property",
		"Module",
		"Struct",
	}
	for _, item in ipairs(items) do
		if vim.tbl_contains(white_list, item.kind) then
			local entry = M.picker_entry.new(item.text, item)
			table.insert(entries, entry)
		end
	end
	local function on_select(entry, winmode)
		if not entry then return end
		local item = entry.data ---@type alex.ffind.QfSymbolEntry
		if item.filename ~= vim.api.nvim_buf_get_name(0) then
			local table = {
				none = "edit ",
				norm = "new ",
				vert = "vnew ",
			}
			vim.cmd(table[winmode] .. item.filename)
		end
		vim.api.nvim_win_set_cursor(0, { item.lnum, item.col - 1 })
	end
	M.open_picker(entries, {
		on_select = on_select
	})
end

function M.document_symbols()
	local clients = vim.lsp.get_clients {
		bufnr = 0
	}
	if #clients == 0 then
		vim.notify("There are no active LSP clients in the current buffer", vim.log.levels.WARN)
		return
	end
	vim.lsp.buf.document_symbol {
		on_list = open_picker_qf_symbol_list
	}
end

function M.workspace_symbols()
	vim.lsp.buf.workspace_symbol("", {
		on_list = open_picker_qf_symbol_list
	})
end

local find_manpage_state = nil

function M.find_manpage()
	local function fetch_manpages(callback)
		if not find_manpage_state then
			find_manpage_state = {
				ready = false,
				callback = callback
			}
		elseif find_manpage_state.ready == true then
			callback(find_manpage_state.entries)
			return
		else
			-- clear previous callback because there can only be one
			-- picker at a time
			find_manpage_state.callback = callback
			return
		end
		local cmd = { "apropos", ".*" }
		vim.system(cmd, { text = true }, function(result)
			local output = result.stdout
			if output == nil then
				error("couldn't grab manpages")
			end
			local entries = {}
			for line in vim.gsplit(output, "\n") do
				local entry, part = string.match(line, "^([^%s]+)%s([^%s]+)")
				if entry then
					table.insert(entries, M.picker_entry.new(entry .. part, nil))
				end
			end
			vim.schedule(function()
				find_manpage_state.callback(entries)
				find_manpage_state.ready = true
				find_manpage_state.entries = entries
			end)
		end)
	end
	local function on_select(selected, winmode)
		if not selected then return end
		if winmode ~= "none" then
			local table = {
				norm = "new",
				vert = "vnew",
			}
			vim.cmd(table[winmode])
		end
		vim.cmd("hide Man " .. selected.text)
	end
	fetch_manpages(function(entries)
		M.open_picker(entries, {
			on_select = on_select
		})
	end)
end

return M
