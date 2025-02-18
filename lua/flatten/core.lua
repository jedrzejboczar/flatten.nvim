local M = {}

local function unblock_guest(guest_pipe, othercmds)
	local response_sock = vim.fn.sockconnect("pipe", guest_pipe, { rpc = true })
	vim.fn.rpcnotify(response_sock, "nvim_exec_lua", "vim.cmd('qa!')", {})
	vim.fn.chanclose(response_sock)

	for _, cmd in ipairs(othercmds) do
		vim.api.nvim_del_autocmd(cmd)
	end
end

local function notify_when_done(pipe, bufnr, callback, ft)
	local quitpre
	local bufunload
	local bufdelete

	quitpre = vim.api.nvim_create_autocmd("QuitPre", {
		buffer = bufnr,
		once = true,
		callback = function()
			unblock_guest(pipe, { bufunload, bufdelete })
			callback(ft)
		end
	})
	bufunload = vim.api.nvim_create_autocmd("BufUnload", {
		buffer = bufnr,
		once = true,
		callback = function()
			unblock_guest(pipe, { quitpre, bufdelete })
			callback(ft)
		end
	})
	bufdelete = vim.api.nvim_create_autocmd("BufDelete", {
		buffer = bufnr,
		once = true,
		callback = function()
			unblock_guest(pipe, { quitpre, bufunload })
			callback(ft)
		end
	})
end

M.edit_files = function(args, response_pipe, guest_cwd)
	local config = require("flatten").config
	local callbacks = config.callbacks
	local focus_first = config.window.focus == "first"
	local open = config.window.open

	callbacks.pre_open()
	if #args > 0 then
		local argstr = ""
		for _, arg in ipairs(args) do
			local p = vim.loop.fs_realpath(arg) or guest_cwd .. '/' .. arg
			if argstr == "" or argstr == nil then
				argstr = p
			else
				argstr = argstr .. " " .. p
			end
		end

		vim.cmd("0argadd " .. argstr)

		if type(open) == "function" then
			-- Pass list of new buffer IDs
			local bufs = vim.api.nvim_list_bufs()
			local start = #bufs - #args
			local newbufs = {}
			for i, buf in ipairs(bufs) do
				if i > start then
					table.insert(newbufs, buf)
				end
			end
			open(newbufs)
		elseif type(open) == "string" then
			local focus = vim.fn.argv(focus_first and 0 or (#args - 1))
			if open == "current" then
				vim.cmd("edit " .. focus)
			elseif open == "split" then
				vim.cmd("split " .. focus)
			elseif open == "vsplit" then
				vim.cmd("vsplit " .. focus)
			else
				vim.cmd("tab " .. focus)
			end
		else
			vim.api.nvim_err_writeln("Flatten: 'config.open.focus' expects a function or string, got " .. type(open))
		end
	else
		-- If there weren't any args, don't open anything
		-- and tell the guest not to block
		return false
	end
	local ft = vim.bo.filetype

	local winnr = vim.api.nvim_get_current_win()
	local bufnr = vim.api.nvim_get_current_buf()
	callbacks.post_open(bufnr, winnr, ft)

	local block = config.block_for[ft] == true
	if block then
		notify_when_done(response_pipe, bufnr, callbacks.block_end, ft)
	end
	return block
end

return M
