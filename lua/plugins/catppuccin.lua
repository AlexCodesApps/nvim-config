return {
	"catppuccin/nvim",
	name = "catppuccin",
	priority = 1000,
	opts = {
		dim_inactive = {
			enabled = true
		},
		custom_highlights = function(colors)
			return {
				MsgArea = { link = 'StatusLine' },
				WinSeparator = { bg = colors.mantle, fg = colors.mantle }
			}
		end
	}
}
