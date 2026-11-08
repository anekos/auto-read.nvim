local M = {}

local default_config = {
	tail_command = "tail",
	-- 開始時に読み込む行数。nil なら先頭から全て
	initial_lines = nil,
	-- ローテーションに追従する (tail -F)
	follow_name = false,
	-- 追記前に末尾行にカーソルがあったウィンドウだけ、新しい末尾行へ追従させる
	follow_cursor = true,
	-- 追記後に 'modified' を下ろす
	reset_modified = false,
	notify = true,
}

local config = vim.deepcopy(default_config)

-- bufnr -> { job = number, autocmd = number, path = string }
local states = {}

local augroup = vim.api.nvim_create_augroup("AutoRead", { clear = true })

function M.setup(opts)
	config = vim.tbl_deep_extend("force", default_config, opts or {})
end

local function notify(message, level)
	level = level or vim.log.levels.INFO
	if config.notify or level >= vim.log.levels.WARN then
		vim.notify("auto-read: " .. message, level)
	end
end

local function resolve_buf(buf)
	if buf == nil or buf == 0 then
		return vim.api.nvim_get_current_buf()
	end
	return buf
end

local function is_empty_buffer(buf)
	return vim.api.nvim_buf_line_count(buf) == 1 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
end

--- 行をバッファの末尾へ追記します。
local function append_lines(buf, lines)
	if #lines == 0 or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local line_count = vim.api.nvim_buf_line_count(buf)

	local following = {}
	if config.follow_cursor then
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_get_buf(win) == buf and vim.api.nvim_win_get_cursor(win)[1] == line_count then
				table.insert(following, win)
			end
		end
	end

	local modifiable = vim.bo[buf].modifiable
	if not modifiable then
		vim.bo[buf].modifiable = true
	end

	-- 空バッファは 1 行の空行なので、それを置き換えます
	local start = is_empty_buffer(buf) and 0 or line_count
	vim.api.nvim_buf_set_lines(buf, start, -1, false, lines)

	if not modifiable then
		vim.bo[buf].modifiable = false
	end

	if config.reset_modified then
		vim.bo[buf].modified = false
	end

	local new_line_count = vim.api.nvim_buf_line_count(buf)
	for _, win in ipairs(following) do
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_set_cursor(win, { new_line_count, 0 })
		end
	end
end

--- jobstart の stdout は改行で分割され、末尾要素は不完全な行です。
--- 次のチャンクの先頭要素と連結して初めて 1 行になります。
local function make_on_stdout(buf)
	local pending = ""

	return function(_, data)
		if not data then
			return
		end
		-- stdout が閉じたことを示す通知
		if #data == 1 and data[1] == "" then
			return
		end

		data[1] = pending .. data[1]
		pending = table.remove(data)

		append_lines(buf, data)
	end
end

function M.stop(buf)
	buf = resolve_buf(buf)

	local state = states[buf]
	if not state then
		notify("tail していません")
		return false
	end

	states[buf] = nil

	pcall(vim.fn.jobstop, state.job)
	pcall(vim.api.nvim_del_autocmd, state.autocmd)

	notify("tail を終了しました: " .. state.path)
	return true
end

--- 指定したファイルを tail し、出力をバッファへ追記します。
---@param path string tail するファイル
---@param opts table|nil { buf = number, lines = number|nil, from_end = boolean }
function M.start(path, opts)
	opts = opts or {}
	local buf = resolve_buf(opts.buf)

	if states[buf] then
		notify("このバッファは既に tail しています: " .. states[buf].path, vim.log.levels.ERROR)
		return false
	end

	if vim.fn.executable(config.tail_command) ~= 1 then
		notify(config.tail_command .. " が見つかりません", vim.log.levels.ERROR)
		return false
	end

	if path == nil or path == "" then
		notify("ファイルを指定してください", vim.log.levels.ERROR)
		return false
	end

	path = vim.fn.fnamemodify(vim.fn.expand(path), ":p")
	local stat = vim.uv.fs_stat(path)
	if not stat or stat.type == "directory" then
		notify("ファイルが存在しません: " .. path, vim.log.levels.ERROR)
		return false
	end

	-- -n の引数。+1 は先頭から、0 は以降の追記のみ
	local count = "+1"
	if opts.from_end then
		count = "0"
	else
		local lines = opts.lines or config.initial_lines
		if lines then
			count = tostring(lines)
		end
	end

	local command = {
		config.tail_command,
		"-n",
		count,
		config.follow_name and "-F" or "-f",
		path,
	}

	local job = vim.fn.jobstart(command, {
		on_stdout = make_on_stdout(buf),
		on_stderr = function(_, data)
			local message = table.concat(data or {}, "\n"):gsub("%s+$", "")
			if message ~= "" then
				notify(message, vim.log.levels.WARN)
			end
		end,
		on_exit = function(_, code)
			if states[buf] then
				states[buf] = nil
				if code ~= 0 then
					notify(config.tail_command .. " が終了コード " .. code .. " で終了しました", vim.log.levels.WARN)
				end
			end
		end,
	})

	if job <= 0 then
		notify(config.tail_command .. " の起動に失敗しました", vim.log.levels.ERROR)
		return false
	end

	local autocmd = vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
		group = augroup,
		buffer = buf,
		callback = function()
			M.stop(buf)
		end,
	})

	states[buf] = { job = job, autocmd = autocmd, path = path }

	notify("tail を開始しました: " .. path)
	return true
end

function M.is_running(buf)
	return states[resolve_buf(buf)] ~= nil
end

function M.tailing_path(buf)
	local state = states[resolve_buf(buf)]
	return state and state.path or nil
end

return M
