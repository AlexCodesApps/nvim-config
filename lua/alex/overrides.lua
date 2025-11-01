if 1 == vim.fn.executable 'hyprctl' then
	---@diagnostic disable-next-line: duplicate-set-field
	vim.notify = function(msg, level, _)
		level = level or vim.log.levels.OFF
		local table = {
			[vim.log.levels.WARN] = { icon = '0', color = 'rgb(FFFF00)' },
			[vim.log.levels.ERROR] = { icon = '3', color = 'rbg(FF0000)' },
		}
		local info = table[level] or {}
		local icon = info.icon or '1'
		local color = info.color or "rbg(0000FF)"
		vim.system {
			'hyprctl',
			'notify',
			icon,
			'3000',
			color,
			msg
		}
	end
end
