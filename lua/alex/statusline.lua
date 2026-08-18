local M = {}
local vimffi = require('alex.vimffi')
local devicons = require('nvim-web-devicons')
local api = require('alex.api')

---@param iden string
---@return vim.api.keyset.get_hl_info
local function hl(iden)
	return vim.api.nvim_get_hl(0, { name = iden, link = true, create = false })
end

local function status_line_hl(group)
	return '%#' .. group .. '#'
end

local function status_line_hl_reset()
	return '%*'
end

local function mode_component()
	local mode = api.mode_info()
	local name
	if mode.pending then
		name = "PENDING"
	elseif mode.major == "x" then
		name = ({
			char = "VISUAL",
			line = "V-LINE",
			block = "V-BLOCK",
		})[mode.range]
	elseif mode.major == "R" then
		name = "REPLACE"
	elseif mode.major == "c" then
		name = "COMMAND"
	elseif mode.major == "i" then
		name = "INSERT"
	elseif mode.major == "s" then
		name = "SELECT"
	else
		name = "NORMAL"
	end
	return table.concat({
		name,
	})
end

local function devicon_component()
	local icon, group = devicons.get_icon_by_filetype(vim.bo.filetype, { default = true })
	return table.concat {
		status_line_hl(group),
		icon,
		status_line_hl_reset()
	}
end

local function macro_record_component()
	local reg = vim.fn.reg_recording()
	if reg == '' then return '' end
	return table.concat {
		status_line_hl('DiagnosticError'),
		'● REC @',
		reg,
		status_line_hl_reset()
	}
end

function M.status_line()
	local orig = vim.o.statusline
	return function()
		if vim.api.nvim_get_current_win() ~= tonumber(vim.g.actual_curwin) then
			return orig
		end
		return table.concat {
			devicon_component(),
			'  ',
			mode_component(),
			' ',
			macro_record_component(),
			' ',
			orig,
		}
	end
end

function M.setup()
	local cb = vimffi.Object.new(M.status_line())
	vim.o.statusline = '%{%' .. cb:vim_script_call() .. '%}'
	-- local theme = require('lualine.themes.gruvbox')
	-- for _, mode in ipairs {
	-- 	'normal', 'insert', 'visual', 'replace', 'command', 'inactive'
	-- } do
	-- 	theme[mode].c.bg = '#0a0c10'
	-- end
	-- require('lualine').setup {
	--
	-- }
end

return M
