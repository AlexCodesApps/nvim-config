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

---@class alex.ffind.Picker
---@field outer { win: integer, buf: integer }
---@field inner { win: integer, buf: integer }
---@field augroup integer
---@field entries alex.ffind.PickerEntry[]
---@field on_select fun(selected: alex.ffind.PickerEntry?, winmode: alex.ffind.WinMode): any
---@field sorter alex.ffind.SortFn
---@field on_cancel? fun(selected: boolean)
---@field state { filtered: alex.ffind.PickerEntry[], c_offset: integer, s_offset: integer, sync_handle: any }

---@type alex.ffind.Picker?
local g_picker = nil

---@param selected? boolean
local function terminate_picker(selected)
	if not g_picker then return end
	vim.api.nvim_del_augroup_by_id(g_picker.augroup)
	vim.api.nvim_buf_delete(g_picker.inner.buf, {
		force = true
	})
	vim.api.nvim_buf_delete(g_picker.outer.buf, {
		force = true
	})
	vim.cmd.stopinsert()
	local on_cancel = g_picker.on_cancel
	g_picker = nil
	if on_cancel then on_cancel(selected or false) end
end

local function get_picker_input()
	return vim.api.nvim_get_current_line()
end

local function picker_entry_window_height()
	assert(g_picker)
	return vim.api.nvim_win_get_height(g_picker.outer.win)
end

local function picker_screen_offset_min()
	return 0
end

local function picker_screen_offset_max()
	assert(g_picker)
	local sheight = picker_entry_window_height()
	return math.max(#g_picker.state.filtered - sheight, 0)
end

local function picker_cursor_offset_min()
	return 0
end

local function picker_cursor_offset_max()
	assert(g_picker)
	return math.min(picker_entry_window_height(), #g_picker.state.filtered) - 1
end

local function picker_draw()
	assert(g_picker)
	local screen_lines = {}
	local sheight = picker_entry_window_height()
	local nentry = math.min(sheight, #g_picker.state.filtered - g_picker.state.s_offset)
	for i = nentry, 1, -1 do
		table.insert(screen_lines, g_picker.state.filtered[i + g_picker.state.s_offset].text)
	end
	vim.api.nvim_buf_set_lines(g_picker.outer.buf, 0, -1, false, screen_lines)
	local cursor_pos
	if nentry ~= 0 then
		cursor_pos = { math.max(nentry - g_picker.state.c_offset, 1), 0 }
	else
		cursor_pos = { 1, 0 }
	end
	vim.api.nvim_win_set_cursor(g_picker.outer.win, cursor_pos)
end

local function reset_picker_window()
	assert(g_picker)
	local input = get_picker_input()
	local function draw()
		g_picker.state.s_offset = picker_screen_offset_min()
		g_picker.state.c_offset = picker_cursor_offset_min()
		picker_draw()
	end
	if input ~= "" then
		local sync_handle = {}
		g_picker.state.sync_handle = sync_handle
		g_picker.sorter(g_picker.entries, input, function(entries)
			if not g_picker or g_picker.state.sync_handle ~= sync_handle then
				return
			end
			g_picker.state.filtered = entries
			draw()
		end)
	else
		g_picker.state.filtered = g_picker.entries
		draw()
	end
end

local function move_cursor_up()
	assert(g_picker)
	local cmax = picker_cursor_offset_max()
	local smax = picker_screen_offset_max()
	if g_picker.state.c_offset == cmax then
		if g_picker.state.s_offset == smax then
			return
		end
		g_picker.state.s_offset = g_picker.state.s_offset + 1
	else
		g_picker.state.c_offset = g_picker.state.c_offset + 1
	end
	picker_draw()
end

local function move_cursor_down()
	assert(g_picker)
	local cmin = picker_cursor_offset_min()
	local smin = picker_screen_offset_min()
	if g_picker.state.c_offset == cmin then
		if g_picker.state.s_offset == smin then
			return
		end
		g_picker.state.s_offset = g_picker.state.s_offset - 1
		picker_draw()
		return
	end
	g_picker.state.c_offset = g_picker.state.c_offset - 1
	picker_draw()
end

local function scroll_screen_up()
	assert(g_picker)
	local smax = picker_screen_offset_max()
	if g_picker.state.s_offset == smax then
		return
	end
	g_picker.state.s_offset = g_picker.state.s_offset + 1
	picker_draw()
end

local function scroll_screen_down()
	assert(g_picker)
	local smin = picker_screen_offset_min()
	if g_picker.state.s_offset == smin then
		return
	end
	g_picker.state.s_offset = g_picker.state.s_offset - 1
	picker_draw()
end

---@return alex.ffind.PickerEntry?
local function get_selected_field()
	assert(g_picker)
	return g_picker.state.filtered[g_picker.state.s_offset + g_picker.state.c_offset + 1]
end

local function run(winmode)
	return function()
		assert(g_picker)
		local selected = get_selected_field()
		local on_select = g_picker.on_select
		terminate_picker(true)
		on_select(selected, winmode)
	end
end

local function move_screen_cursor_top()
	assert(g_picker)
	g_picker.state.s_offset = picker_screen_offset_max()
	g_picker.state.c_offset = picker_cursor_offset_max()
	picker_draw()
end

local function get_scroll()
	assert(g_picker)
	local sheight = picker_entry_window_height()
	return math.min(sheight - 1, vim.wo[g_picker.outer.win].scroll)
end

local function scroll_screen_up_u()
	assert(g_picker)
	local smax = picker_screen_offset_max()
	local new_offset = g_picker.state.s_offset + get_scroll()
	g_picker.state.s_offset = math.min(smax, new_offset)
	picker_draw()
end

local function scroll_screen_down_d()
	assert(g_picker)
	local smin = picker_screen_offset_min()
	local new_offset = g_picker.state.s_offset - get_scroll()
	g_picker.state.s_offset = math.max(smin, new_offset)
	picker_draw()
end

local function move_screen_cursor_bottom()
	assert(g_picker)
	g_picker.state.s_offset = picker_screen_offset_min()
	g_picker.state.c_offset = picker_cursor_offset_min()
	picker_draw()
end

---@class alex.ffind.OpenPickerConfig
---@field title? string
---@field on_select fun(selected: alex.ffind.PickerEntry?, winmode: alex.ffind.WinMode): any
---@field sorter? alex.ffind.SortFn
---@field on_cancel? fun(selected: boolean)

---@param entries alex.ffind.PickerEntry[]
---@param config alex.ffind.OpenPickerConfig
function M.open_picker(entries, config)
	local title = config.title or "Finder"
	local on_select = config.on_select
	local sorter = config.sorter or M.default_sorter
	local on_cancel = config.on_cancel
	terminate_picker(false)
	local outer_winbuf = vim.api.nvim_create_buf(false, true)
	local inner_winbuf = vim.api.nvim_create_buf(false, true)
	local outer_window = vim.api.nvim_open_win(outer_winbuf, false, {
		title = title,
		title_pos = "center",
		relative = "editor",
		style = "minimal",
		border = "rounded",
		width = math.floor(vim.o.columns * 0.7),
		height = math.floor(vim.o.lines * 0.7),
		row = math.floor(vim.o.lines * 0.15),
		col = math.floor(vim.o.columns * 0.15),
	})
	vim.wo[outer_window].winhl = 'Normal:Normal,FloatBorder:Normal'
	local inner_window = vim.api.nvim_open_win(inner_winbuf, true, {
		relative = "win",
		win = outer_window,
		style = "minimal",
		border = "rounded",
		width = vim.api.nvim_win_get_width(outer_window),
		height = 1,
		row = vim.api.nvim_win_get_height(outer_window) + 1,
		col = -1,
	})
	vim.wo[inner_window].winhl = 'Normal:Normal,FloatBorder:Normal'
	local augroup = vim.api.nvim_create_augroup("alex.ffind", {
		clear = true
	})
	g_picker = {
		inner = { win = inner_window, buf = inner_winbuf },
		outer = { win = outer_window, buf = outer_winbuf },
		augroup = augroup,
		entries = entries,
		on_select = on_select,
		sorter = sorter,
		on_cancel = on_cancel,
		state = {
			filtered = entries,
			c_offset = picker_cursor_offset_min(),
			s_offset = picker_screen_offset_min(),
		}
	}
	vim.wo[outer_window].cursorline = true
	vim.api.nvim_create_autocmd("BufLeave", {
		group = augroup,
		buffer = inner_winbuf,
		callback = terminate_picker,
	})
	vim.api.nvim_create_autocmd("WinLeave", {
		group = augroup,
		callback = terminate_picker,
	})
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = augroup,
		buffer = inner_winbuf,
		callback = reset_picker_window,
	})
	vim.keymap.set("n", "<Esc>", terminate_picker, { buffer = true })
	vim.keymap.set({ "n", "i" }, "<Enter>", run("none"), { buffer = true })
	vim.keymap.set({ "n", "i" }, "<C-v>", run("vert"), { buffer = true })
	vim.keymap.set({ "n", "i" }, "<C-n>", run("norm"), { buffer = true })
	vim.keymap.set("n", "k", move_cursor_up, { buffer = true })
	vim.keymap.set("n", "j", move_cursor_down, { buffer = true })
	vim.keymap.set("i", "<C-k>", move_cursor_up, { buffer = true })
	vim.keymap.set("i", "<C-j>", move_cursor_down, { buffer = true })
	vim.keymap.set({"n", "i"}, "<C-y>", scroll_screen_up, { buffer = true })
	vim.keymap.set({"n", "i"}, "<C-e>", scroll_screen_down, { buffer = true })
	vim.keymap.set({"n", "i"}, "<C-u>", scroll_screen_up_u, { buffer = true })
	vim.keymap.set({"n", "i"}, "<C-d>", scroll_screen_down_d, { buffer = true })
	vim.keymap.set("n", "gg", move_screen_cursor_top, { buffer = true })
	vim.keymap.set("n", "G", move_screen_cursor_bottom, { buffer = true })
	vim.cmd.startinsert()
	picker_draw()
end

---@type alex.ffind.SortFn
function M.default_sorter(entries, input, callback)
	callback(vim.fn.matchfuzzy(entries, input, {
		key = "text",
	}))
end

---@param winmode alex.ffind.WinMode
---@param path string
local function edit_file(winmode, path)
	local table = {
		none = "e ",
		norm = "new ",
		vert = "vnew ",
	}
	vim.cmd(table[winmode] .. vim.fn.fnameescape(path))
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
		edit_file(winmode, path .. "/" .. line)
	end
	fetch_recursive_files(path, "", exclude_pattern, gitignore, function(files)
		local entries = M.picker_entry.from_list(files)
		M.open_picker(entries, {
			title = "Find File",
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
		edit_file(winmode, file)
		local row = entry.data.row
		vim.api.nvim_win_set_cursor(0, { row, 0 })
	end
	M.open_picker({}, {
		title = "Live Grep",
		on_select = on_select,
		sorter = sorter,
		on_cancel = on_cancel,
	})
end

function M.find_buffer()
	local buffers = vim.api.nvim_list_bufs()
	local entries = {}
	for _, buffer in ipairs(buffers) do
		if vim.api.nvim_buf_is_loaded(buffer) then
			local filename = vim.api.nvim_buf_get_name(buffer)
			local text = ("%d %s"):format(buffer, filename)
			local entry = M.picker_entry.new(text, buffer)
			table.insert(entries, entry)
		end
	end
	local function on_select(entry, winmode)
		if not entry then return nil end
		local buffer = entry.data
		if winmode ~= "none" then
			local table = {
				norm = "new",
				vert = "vnew",
			}
			vim.cmd(table[winmode])
		end
		vim.cmd.buffer(tostring(buffer))
	end
	M.open_picker(entries, {
		title = "Find Buffer",
		on_select = on_select
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
		title = "Browse Help",
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
		title = "LSP Symbols",
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

local manpage_promise = nil
function M.find_manpage()
	local function fetch_manpage_entries(callback)
		if manpage_promise ~= nil then
			if not manpage_promise.result then
				table.insert(manpage_promise.listeners, callback)
			else
				callback(manpage_promise.result)
			end
			return
		end
		manpage_promise = {
			listeners = { callback },
			result = nil,
		}
		vim.system({ "apropos", ".*" }, { text = true }, function(obj)
			if obj.stdout == nil then
				error("couldn't grab manpages")
			end
			local entries = {}
			for line in vim.gsplit(obj.stdout, "\n") do
				local entry, part = string.match(line, "^([^%s]+)%s([^%s]+)")
				if entry then
					table.insert(entries, M.picker_entry.new(entry .. part, nil))
				end
			end
			manpage_promise.result = entries
			for _, listener in ipairs(manpage_promise.listeners) do
				vim.schedule(function() listener(entries) end)
			end
			manpage_promise.listeners = nil
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
	fetch_manpage_entries(function(entries)
		M.open_picker(entries, {
			title = "Browse Manpages",
			on_select = on_select
		})
	end)
end

local cached_colorschemes = nil
function M.find_colorscheme()
	if not cached_colorschemes then
		cached_colorschemes = {}
		local rtp = vim.o.runtimepath
		for _, path in ipairs(vim.fn.globpath(rtp, "**/colors/*", false, true)) do
			local name, ext = path:match("([^%./]+)%.([^%./]+)$")
			if ext == "vim" or ext == "lua" and name then
				table.insert(cached_colorschemes, M.picker_entry.new(name, nil))
			end
		end
	end
	local function on_select(selected, _)
		if not selected then return end
		vim.cmd.colorscheme(selected.text)
	end
	M.open_picker(cached_colorschemes, {
		title = "Choose Colorscheme",
		on_select = on_select
	})
end

return M
