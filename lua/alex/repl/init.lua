local M = {}

local job = require('alex.repl.job')

local ghci_repl = nil

---@param input string[]
---@return string|string[]
local function escape_ghci_input(input)
	table.insert(input, 1, ':{')
	table.insert(input, ':}')
	return input
end

---@return alex.repl.job.Repl?
function M.ghci_repl()
	if ghci_repl then return ghci_repl end
	ghci_repl = job.Repl.new('GHCI', {'ghci'}, {
		escape_input = escape_ghci_input
	})
	return ghci_repl
end

local cabal_repl = nil

function M.cabal_repl()
	if cabal_repl then return cabal_repl end
	cabal_repl = job.Repl.new('Cabal', {'cabal', 'repl'}, {
		escape_input = escape_ghci_input
	})
	return cabal_repl
end

local scheme_repl = nil

---@return alex.repl.job.Repl?
function M.scheme_repl()
	if scheme_repl then return scheme_repl end
	scheme_repl = job.Repl.new('Scheme', {'scheme'}, {
		escape_input = function(input)
			table.insert(input, 1, '(begin ')
			table.insert(input, ')')
			input = table.concat(input, ' ')
			return input
		end
	})
	return scheme_repl
end


local lua_repl = nil

---@return alex.repl.job.Repl?
function M.lua_repl()
	if lua_repl then return lua_repl end
	lua_repl = job.Repl.new('Lua', {'lua'}, {
		escape_input = function(lines)
			local text = table.concat(lines, '\n')
			local tree = vim.treesitter.get_string_parser(text, 'lua')
							:parse()
			if tree then
				local root = tree[1]:root()
				if root:has_error() then
					return text
				end
				if root:named_child_count() == 1
					and root:named_child(0):type() == 'function_call' then
					return text
				end
			end
			return 'do ' .. text .. ' end'
		end
	})
	return lua_repl
end

local node_repl = nil

---@return alex.repl.job.Repl?
function M.node_repl()
	if node_repl then return node_repl end
	node_repl = job.Repl.new('Node', {'node'}, {
		escape_input = 'none'
	})
	return node_repl
end

local python_repl = nil
---@return alex.repl.job.Repl?
function M.python_repl()
	if python_repl then return python_repl end
	python_repl = job.Repl.new('Python', {'python'}, {
		escape_input = function(lines)
			---@param line string
			lines = vim.tbl_map(function(line)
				local out = {}
				local len = line:len()
				for i = 1, len do
					local c = line:sub(i, i)
					local b = c:byte()
					if c == '\\' then
						out[#out+1] = '\\\\'
					elseif c == '"' then
						out[#out+1] = '\\"'
					elseif c == '\n' then
						error('this is impossible')
					elseif c == '\r' then
						out[#out+1] = '\\r'
					elseif c == '\t' then
						out[#out+1] = '\\t'
					elseif b < 32 or b == 127 then
						out[#out+1] = string.format('\\x%02x', b)
					else
						out[#out+1] = c
					end
				end
				return '"' .. table.concat(out) .. '\\n"'
			end, lines)
			table.insert(lines, 1, 'exec(')
			table.insert(lines, ')')
			return lines
		end
	})
	return python_repl
end

---@type table<string, { repl: fun(): alex.repl.job.Repl? }>
M.filetype_repl_table = {
	lua = { repl = M.lua_repl },
	scheme = { repl = M.scheme_repl },
	haskell = { repl = M.ghci_repl },
	javascript = { repl = M.node_repl },
	python = { repl = M.python_repl }
}

---@param buf integer
---@return alex.repl.job.Repl?
function M.buffer_repl(buf)
	local entry = M.filetype_repl_table[vim.bo[buf].filetype]
	if not entry then return end
	return entry.repl()
end

return M
