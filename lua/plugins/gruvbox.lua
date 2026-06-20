return {
	"ellisonleao/gruvbox.nvim",
	priority = 1000,
	opts = {
		terminal_colors = true, -- add neovim terminal colors
		undercurl = true,
		underline = true,
		bold = false,
		italic = {
			strings = true,
			emphasis = true,
			comments = true,
			operators = false,
			folds = true,
		},
		strikethrough = true,
		invert_selection = false,
		invert_signs = false,
		invert_tabline = false,
		inverse = true, -- invert background for search, diffs, statuslines and errors
		contrast = "hard", -- can be "hard", "soft" or empty string
		palette_overrides = {},
		overrides = {
			Pmenu = { link = 'Normal' },
			PmenuSbar = { link = 'Cursor' },
			PmenuThumb = { bg = 'white' },
			StatusLine = { link = 'Normal' },
			StatusLineNC = { link = 'NonText' },
			StatusLineTerm = { link = 'Normal' },
			LspReferenceTarget = {},
			['@lsp.type.class'] = { link = '@lsp.type.variable' },
			['@lsp.type.enum'] = { link = '@lsp.type.variable' },
			['@lsp.type.event'] = { link = '@lsp.type.variable' },
			['@lsp.type.function'] = { link = '@lsp.type.variable' },
			['@lsp.type.method'] = { link = '@lsp.type.variable' },
			['@lsp.type.modifier'] = { link = '@lsp.type.variable' },
			['@lsp.type.number'] = { link = '@lsp.type.variable' },
			['@lsp.type.operator'] = { link = '@lsp.type.variable' },
			['@lsp.type.struct'] = { link = '@lsp.type.variable' },
			['@lsp.type.type'] = { link = '@lsp.type.variable' },
			['@lsp.type.typeParameter'] = { link = '@lsp.type.variable' },
			['@lsp.type.property'] = { link = '@lsp.type.variable' },
			['@lsp.type.parameter'] = { link = '@lsp.type.variable' },
		},
		dim_inactive = false,
		transparent_mode = true,
	}
}
