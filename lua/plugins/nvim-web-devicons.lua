local overrides = {
	{{ 'json', 'json5', 'jsonc', 'jsonl' }, { icon = '', }},
	{{ '.vimrc', '_vimrc', '.gvimrc', '_gvimrc', 'vim' }, { icon = '', }},
	{{ 'js' }, { icon = '' }},
	{{ 'markdown' }, { icon = '' }},
}

return {
	"nvim-tree/nvim-web-devicons",
	config = function()
		local devicons = require('nvim-web-devicons')
		devicons.setup()
		local icons = devicons.get_icons()
		local patch = {}
		for _, pair in pairs(overrides) do
			local types = pair[1]
			local conf = pair[2]
			for _, type in ipairs(types) do
				local orig = icons[type]
				patch[type] = vim.tbl_extend('force', orig, conf)
			end
		end
		devicons.set_icon(patch)
	end
}
