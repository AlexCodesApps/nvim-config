vim.diagnostic.config{ virtual_text = true }

local filetype_tabsize_table = {
	html = 2,
	css = 2,
}

vim.api.nvim_create_autocmd('LspAttach', {
	callback = function (_)
		local tab_width = filetype_tabsize_table[vim.bo.filetype]
		if tab_width ~= nil then
			vim.bo.tabstop = tab_width
			vim.bo.shiftwidth = tab_width
		end
	end
})

vim.api.nvim_create_user_command('LspRestart', function ()
	local lsps = vim.lsp.get_clients()
	for _, lsp in ipairs(lsps) do
		local name = lsp.name
		vim.lsp.enable(name, false)
		vim.lsp.enable(name, true)
	end
end, { desc = "restarts all running language servers" })

vim.lsp.enable('luals')
vim.lsp.enable('ts_ls')
vim.lsp.enable('vscode_css_lsp')
vim.lsp.enable('vscode_html_lsp')
vim.lsp.enable('clangd')
vim.lsp.enable('emmet_language_server')
vim.lsp.enable('rust-analyzer')
