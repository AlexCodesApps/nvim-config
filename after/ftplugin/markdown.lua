vim.wo.conceallevel = 1
vim.wo.wrap = true
vim.wo.relativenumber = false
vim.keymap.set('n', 'j', 'gj', { buffer = true })
vim.keymap.set('n', 'k', 'gk', { buffer = true })
local function get_parent_section(node)
	node = node or vim.treesitter.get_node()
	while node and node:type() ~= 'section' do
		node = node:parent()
	end
	return node
end

---@param node TSNode?
local function get_child_section(node)
	node = node or get_parent_section()
	if not node then return end
    for child in node:iter_children() do
		return child:next_named_sibling()
    end
end

local function goto_node(node)
	if not node then return end
	local row, col = node:start()
	vim.api.nvim_win_set_cursor(0, { row+1, col })
end

vim.keymap.set('n', '[n', function()
	local node = get_parent_section()
	if not node then return end
	local next = node:prev_named_sibling()
	goto_node(next)
end, { buffer = true })

vim.keymap.set('n', ']n', function()
	local node = get_parent_section()
	if not node then return end
	local next = node:next_named_sibling()
	goto_node(next)
end, { buffer = true })

vim.keymap.set('n', 'g[n', function()
	local node = get_parent_section():parent()
	if not node then return end
	node = get_parent_section(node)
	goto_node(node)
end, { buffer = true })

vim.keymap.set('n', 'g]n', function()
	local node = get_child_section()
	goto_node(node)
end, { buffer = true })
