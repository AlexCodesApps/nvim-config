local api = require('alex.api')

if api.lsp_client_available('luals') then
	vim.treesitter.stop()
end
