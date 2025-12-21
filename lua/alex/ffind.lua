local M = {}

local INTERNAL_KEY = {} -- to use as a private field key value

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

---@alias alex.ffind.WinMode "split"|"hsplit"|"vsplit"

---@class alex.ffind.Actions
---@field on_select fun(entry: alex.ffind.PickerEntry?, winmode: alex.ffind.WinMode)
---@field on_cancel? fun(selected: boolean)
---@field to_qflist? fun(entries: alex.ffind.PickerEntry[])
---@field to_loclist? fun(entries: alex.ffind.PickerEntry[])

---@param list string[]
---@return alex.ffind.PickerEntry[]
function M.picker_entry.from_list(list)
	local function helper(text)
		return M.picker_entry.new(text, nil)
	end
	return vim.tbl_map(helper, list)
end

local function qflist_next()
	pcall(function() vim.cmd("cnext") end)
end

---@class alex.ffind.Picker
---@field outer { win: integer, buf: integer }
---@field inner { win: integer, buf: integer }
---@field augroup integer
---@field entries alex.ffind.PickerEntry[]
---@field actions alex.ffind.Actions
---@field sorter alex.ffind.SortFn
---@field state { filtered: alex.ffind.PickerEntry[], c_offset: integer, s_offset: integer, sync_handle: any }

---@type alex.ffind.Picker?
local g_picker = nil

---@class alex.ffind.NBProcessStdoutOpts
---@field cancel? fun(): boolean
---@field yield_count? integer

---@generic T
---@param input string
---@param transform fun(line: string): T?
---@param callback fun(entries: T[])
---@param opts? alex.ffind.NBProcessStdoutOpts
local function nonblocking_process_stdout(input, transform, callback, opts)
	opts = opts or {}
	local yield_count = opts.yield_count or 50
	local cancel = opts.cancel
	local function yield()
		local co = coroutine.running()
			vim.schedule(function()
				if not cancel or not cancel() then
					coroutine.resume(co)
				end
			end)
		coroutine.yield()
	end
	local function run(cb)
		coroutine.resume(coroutine.create(cb))
	end
	run(function()
		local entries = {}
		local i = 0
		for line in vim.gsplit(input, "\n") do
			local entry = transform(line)
			if entry then
				table.insert(entries, entry)
			end
			i = i + 1
			if i >= yield_count then
				i = 0
				yield()
			end
		end
		yield()
		callback(entries)
	end)
end

---@param cwd string
---@param prefix? string
---@param exclude_pattern? string
---@param gitignore boolean
---@param callback fun(files: alex.ffind.PickerEntry[])
local function fetch_recursive_files(cwd, prefix, exclude_pattern, gitignore, callback)
	prefix = prefix or ""
	local cmd
	if gitignore then
		cmd = { "rg", "--files" }
	else
		cmd = { "rg", "-uu", "--files" }
	end
	vim.system(cmd, {
		cwd = cwd,
	}, function(result)
		local output = result.stdout
		assert(output)
		local function transform(line)
			if line ~= "" and (not exclude_pattern or line:match(exclude_pattern)) then
				return M.picker_entry.new(line, nil)
			end
			return nil
		end
		nonblocking_process_stdout(output, transform, callback, {
			yield_count = 500,
		})
	end)
end

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
	local on_cancel = g_picker.actions.on_cancel
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
	local cursor_pos = { math.max(nentry - g_picker.state.c_offset, 1), 0 }
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
---@field actions alex.ffind.Actions
---@field sorter? alex.ffind.SortFn

---@param entries alex.ffind.PickerEntry[]
---@param config alex.ffind.OpenPickerConfig
function M.open_picker(entries, config)
	local title = config.title or "Finder"
	local actions = config.actions
	local sorter = config.sorter or M.default_sorter
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
		actions = actions,
		sorter = sorter,
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
	local function run_on_selected(winmode)
		return function()
			assert(g_picker)
			local selected = get_selected_field()
			local cb = g_picker.actions.on_select
			terminate_picker(true)
			cb(selected, winmode)
		end
	end
	local function run_to_qflist()
		assert(g_picker)
		local cb = g_picker.actions.to_qflist
		if not cb then return end
		local filtered = g_picker.state.filtered
		terminate_picker(true)
		cb(filtered)
	end
	local function run_to_loclist()
		assert(g_picker)
		local cb = g_picker.actions.to_loclist
		if not cb then return end
		local filtered = g_picker.state.filtered
		terminate_picker(true)
		cb(filtered)
	end
	local function run_to_buffer()
		assert(g_picker)
		local lines = vim.tbl_map(function(entry)
			return entry.text
		end, g_picker.state.filtered)
		vim.cmd.new()
		vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
	end
	vim.keymap.set("n", "<Esc>", terminate_picker, { buffer = true })
	vim.keymap.set({ "n", "i" }, "<Enter>", run_on_selected("split"), { buffer = true })
	vim.keymap.set({ "n", "i" }, "<C-v>", run_on_selected("vsplit"), { buffer = true })
	vim.keymap.set({ "n", "i" }, "<C-n>", run_on_selected("hsplit"), { buffer = true })
	vim.keymap.set({ "n", "i" }, "<C-q>", run_to_qflist, { buffer = true })
	vim.keymap.set({ "n", "i" }, "<C-l>", run_to_loclist, { buffer = true })
	vim.keymap.set("n", "k", move_cursor_up, { buffer = true })
	vim.keymap.set("n", "j", move_cursor_down, { buffer = true })
	vim.keymap.set("i", "<C-k>", move_cursor_up, { buffer = true })
	vim.keymap.set("i", "<C-j>", move_cursor_down, { buffer = true })
	vim.keymap.set({"n", "i" }, "<C-b>", run_to_buffer, { buffer = true })
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
	local handle = assert(g_picker).state.sync_handle
	local function yield()
		local co = coroutine.running()
		vim.schedule(function()
			if g_picker and g_picker.state.sync_handle == handle then
				coroutine.resume(co)
			end
		end)
		coroutine.yield()
	end
	local function run(cb)
		coroutine.resume(coroutine.create(cb))
	end
	local function sorted_insert(tbl, ent)
		local score = ent[INTERNAL_KEY]
		local low = 1
		local high = #tbl + 1
		while low < high do
			local g = math.floor((low + high) / 2)
			local score2 = tbl[g][INTERNAL_KEY]
			if score2 >= score then
				low = g + 1
			else
				high = g
			end
		end
		table.insert(tbl, low, ent)
	end
	run(function()
		local result = {}
		local i = 0
		for _, entry in ipairs(entries) do
			local lists = vim.fn.matchfuzzypos({ entry.text }, input)
			if #lists[1] ~= 0 then
				entry[INTERNAL_KEY] = lists[3][1] -- The entries score is stored here
				sorted_insert(result, entry)
			end
			i = i + 1
			if i == 100 then
				i = 0
				yield()
			end
		end
		callback(result)
	end)
end

---@param winmode alex.ffind.WinMode
---@param path string
local function edit_file(winmode, path)
	local table = {
		split = "e ",
		hsplit = "new ",
		vsplit = "vnew ",
	}
	if vim.api.nvim_get_current_buf() ~= vim.fn.bufnr(path) then
		vim.cmd(table[winmode] .. vim.fn.fnameescape(path))
	end
end

---@class alex.ffind.FindFileConfig
---@field cwd? string
---@field exclude_pattern? string
---@field gitignore? boolean

---@param config? alex.ffind.FindFileConfig
function M.find_file(config)
	config = config or {}
	local cwd = config.cwd or vim.fn.getcwd()
	local exclude_pattern = config.exclude_pattern
	local gitignore = config.gitignore or false
	---@param entry alex.ffind.PickerEntry?
	---@param winmode alex.ffind.WinMode
	local function on_select(entry, winmode)
		if not entry then return end
		local line = entry.text
		local path = vim.fs.joinpath(cwd, line)
		edit_file(winmode, path)
	end
	---@param entries alex.ffind.PickerEntry[]
	local function to_qflist(entries)
		local qflist = vim.tbl_map(function(entry)
			local line = entry.text
			local path = vim.fs.joinpath(cwd, line)
			return  {
				filename = path,
				lnum = 1,
				col = 1,
				text = line,
			}
		end, entries)
		vim.fn.setqflist({}, "r", {
			title = "Find File results",
			items = qflist,
		})
		qflist_next()
	end
	local actions = { ---@type alex.ffind.Actions
		on_select = on_select,
		to_qflist = to_qflist,
	}
	fetch_recursive_files(cwd, "", exclude_pattern, gitignore, function(entries)
		M.open_picker(entries, {
			title = "Find File",
			actions = actions,
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
			running_future = nil
			if not g_picker then return end
			local function transform(line)
				local file, row = string.match(line, "^([^:]+):(%d+):")
				if not file then return nil end
				return M.picker_entry.new(line, { file = file, row = tonumber(row) })
			end
			local handle = g_picker.state.sync_handle
			local function cancel()
				return not g_picker or g_picker.state.sync_handle ~= handle
			end
			nonblocking_process_stdout(result.stdout, transform, callback, { cancel = cancel })
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
	---@param entries alex.ffind.PickerEntry[]
	local function to_qflist(entries)
		local qflist = vim.tbl_map(function(entry)
			local file = entry.data.file
			local row = entry.data.row
			return {
				filename = file,
				lnum = row,
				col = 1,
				text = entry.text,
			}
		end, entries)
		vim.fn.setqflist({}, "r", {
			title = "Live Grep results",
			items = qflist,
		})
		qflist_next()
	end
	local actions = { ---@type alex.ffind.Actions
		on_select = on_select,
		on_cancel = on_cancel,
		to_qflist = to_qflist,
	}
	M.open_picker({}, {
		title = "Live Grep",
		sorter = sorter,
		actions = actions,
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
		if winmode ~= "split" then
			local table = {
				hsplit = "new",
				vsplit = "vnew",
			}
			vim.cmd(table[winmode])
		end
		vim.cmd.buffer(tostring(buffer))
	end
	---@param entries_ alex.ffind.PickerEntry[]
	local function to_qflist(entries_)
		local qflist = vim.tbl_map(function(entry)
			local bufnr = entry.data
			local bufname = vim.api.nvim_buf_get_name(bufnr)
			if bufname == "" then
				bufname = tostring(bufnr)
			end
			local pos = vim.api.nvim_buf_get_mark(bufnr, '"')
			return {
				bufnr = bufnr,
				text = bufname,
				lnum = pos[1],
				col = pos[2],
			}
		end, entries_)
		vim.fn.setqflist({}, "r", {
			title = "Find Buffer results",
			items = qflist,
		})
		qflist_next()
	end
	M.open_picker(entries, {
		title = "Find Buffer",
		actions = {
			on_select = on_select,
			to_qflist = to_qflist,
		}
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
			split = "",
			hsplit = "",
			vsplit = "vert ",
		}
		local help = entry.text
		vim.cmd(table[winmode] .. "help " .. help)
	end
	M.open_picker(cached_help_entries, {
		title = "Browse Help",
		actions = {
			on_select = on_select,
		},
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
				split = "edit ",
				hsplit = "new ",
				vsplit = "vnew ",
			}
			vim.cmd(table[winmode] .. item.filename)
		end
		vim.api.nvim_win_set_cursor(0, { item.lnum, item.col - 1 })
	end
	---@param entries_ alex.ffind.PickerEntry[]
	local function to_qflist(entries_)
		local qflist = vim.tbl_map(function(entry)
			return entry.data
		end, entries_)
		vim.fn.setqflist({}, "r", {
			title = "LSP Symbol results",
			items = qflist,
		})
		qflist_next()
	end
	M.open_picker(entries, {
		title = "LSP Symbols",
		actions = {
			on_select = on_select,
			to_qflist = to_qflist,
		}
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

local manpage_cache = nil
local function fetch_manpage_entries(callback)
	if manpage_cache ~= nil then
		if not manpage_cache.result then
			table.insert(manpage_cache.listeners, callback)
		else
			callback(manpage_cache.result)
		end
		return
	end
	manpage_cache = {
		listeners = { callback },
		result = nil,
	}
	vim.system({ "apropos", "." }, { text = true }, function(obj)
		if obj.stdout == nil then
			error("couldn't grab manpages")
		end
		local function transform(line)
			local entry, part = string.match(line, "^([^%s]+)%s([^%s]+)")
			if not entry then return nil end
			return M.picker_entry.new(entry .. part, nil)
		end
		nonblocking_process_stdout(obj.stdout, transform, function(entries)
			manpage_cache.result = entries
			for _, listener in ipairs(manpage_cache.listeners) do
				listener(entries)
			end
			manpage_cache.listeners = nil
		end)
	end)
end

function M.find_manpage()
	local function on_select(selected, winmode)
		if not selected then return end
		if winmode ~= "split" then
			local table = {
				hsplit = "new",
				vsplit = "vnew",
			}
			vim.cmd(table[winmode])
		end
		vim.cmd("hide Man " .. selected.text)
	end
	fetch_manpage_entries(function(entries)
		M.open_picker(entries, {
			title = "Browse Manpages",
			actions = {
				on_select = on_select,
			}
		})
	end)
end

local cached_colorschemes = nil
function M.find_colorscheme()
	if not cached_colorschemes then
		cached_colorschemes = {}
		local rtp = vim.o.runtimepath
		for _, path in ipairs(vim.fn.globpath(rtp, "**/colors/*", false, true)) do
			local name, ext = path:gsub("\\", "/"):match("([^%./]+)%.([^%./]+)$")
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
		actions = {
			on_select = on_select
		}
	})
end

return M
