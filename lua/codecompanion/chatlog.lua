local M = {}

M.chat_log_dir = vim.fn.expand("~/codecompanion_chats/")
if vim.fn.isdirectory(M.chat_log_dir) == 0 then
  vim.fn.mkdir(M.chat_log_dir, "p")
end

local DEBOUNCE_DELAY = 300 -- milliseconds

local function write_buffer_to_file(bufnr, file_path)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, "\n")
  local fd, err = io.open(file_path, "w")
  if not fd then
    vim.notify("Error opening file " .. file_path .. ": " .. err, vim.log.levels.ERROR)
    return
  end
  local ok, write_err = fd:write(content)
  if not ok then
    vim.notify("Error writing to file " .. file_path .. ": " .. write_err, vim.log.levels.ERROR)
  end
  fd:close()
end

function M.start_chat_log(bufnr)
  local timestamp = os.date("%Y%m%d-%H%M%S")
  local file_path = M.chat_log_dir .. "/chat_" .. timestamp .. ".txt"
  vim.api.nvim_buf_set_var(bufnr, "chat_log_file", file_path)

  local fd, err = io.open(file_path, "w")
  if fd then
    local header = "Conversation started on: " .. os.date("%c") .. "\n\n"
    fd:write(header)
    fd:close()
  else
    vim.notify("Unable to create chat log at " .. file_path .. ": " .. err, vim.log.levels.ERROR)
    return
  end

  -- Create corresponding metadata file.
  local meta_file = M.chat_log_dir .. "/chat_" .. timestamp .. ".metadata"
  local meta_fd, meta_err = io.open(meta_file, "w")
  if meta_fd then
    local header = "Conversation started on: " .. os.date("%c") .. "\n\n"
    local metadata = {
      created_on = os.date("%c"),
      chat_id = timestamp,
      initial_header = header,
      strategy = "chat"  -- Added default strategy field.
    }
    meta_fd:write(vim.fn.json_encode(metadata))
    meta_fd:close()
  else
    vim.notify("Unable to create chat metadata at " .. meta_file .. ": " .. meta_err, vim.log.levels.ERROR)
  end

  local timer = nil

  local function schedule_write()
    if timer then
      timer:stop()
      timer = nil
    end
    timer = vim.defer_fn(function()
      write_buffer_to_file(bufnr, file_path)
      timer = nil
    end, DEBOUNCE_DELAY)
  end

  vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI"}, {
    buffer = bufnr,
    callback = schedule_write,
  })
end

return M
