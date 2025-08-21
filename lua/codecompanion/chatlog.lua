local config = require("codecompanion.config")

local M = {}

local sessions = {}

local function ensure_dir(path)
  if vim.fn.isdirectory(path) == 0 then
    vim.fn.mkdir(path, "p")
  end
end

local function now_iso()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function safe_json_encode(tbl)
  local ok, res = pcall(vim.json.encode, tbl)
  if ok then
    return res
  end
  return nil
end

local function read_json(path)
  local fd = io.open(path, "r")
  if not fd then
    return nil
  end
  local content = fd:read("*a")
  fd:close()
  local ok, decoded = pcall(vim.json.decode, content)
  if ok then
    return decoded
  end
  return nil
end

local function write_json(path, tbl)
  local json = safe_json_encode(tbl)
  if not json then
    return false
  end
  local fd, err = io.open(path, "w")
  if not fd then
    vim.notify("Error opening file " .. path .. ": " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  fd:write(json)
  fd:close()
  return true
end

local function append_line(path, line)
  local fd, err = io.open(path, "a")
  if not fd then
    vim.notify("Error opening file " .. path .. ": " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  fd:write(line .. "\n")
  fd:close()
  return true
end

local function heuristic_title(text, max_len)
  text = text or ""
  -- Strip code fences and markdown headings
  text = text:gsub("```[%w_%-]*\n?", ""):gsub("```", "")
  text = text:gsub("^#+%s*", "")
  text = text:gsub("\r", "")
  local first_line = text:match("[^\n]+") or text
  local words = {}
  for w in first_line:gmatch("%S+") do
    words[#words + 1] = w
    if #words >= 8 then
      break
    end
  end
  local title = table.concat(words, " ")
  if #title > max_len then
    title = title:sub(1, max_len)
  end
  return title ~= "" and title or os.date("%Y-%m-%d")
end

function M.start_session(chat)
  local cfg = config.chatlog or {}
  if cfg.enabled == false then
    return
  end

  local dir = vim.fs.normalize(cfg.dir)
  ensure_dir(dir)

  local chat_id = os.date("%Y%m%d-%H%M%S") .. "-" .. tostring(chat.id)
  local base = vim.fs.joinpath(dir, "chat_" .. chat_id)
  local paths = {
    jsonl = base .. ".jsonl",
    meta = base .. ".meta.json",
  }

  local metadata = {
    version = 1,
    chat_id = chat_id,
    created_on = now_iso(),
    strategy = "chat",
    adapter = chat.adapter and chat.adapter.name or nil,
    model = chat.adapter and chat.adapter.schema and chat.adapter.schema.model.default or nil,
    title = nil,
    counts = { messages = 0 },
  }

  write_json(paths.meta, metadata)
  sessions[chat.bufnr] = {
    bufnr = chat.bufnr,
    paths = paths,
    metadata = metadata,
    first_user_logged = false,
    debounce_ms = cfg.debounce_ms or 500,
  }

  -- Stop session when buffer is wiped
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufUnload" }, {
    buffer = chat.bufnr,
    callback = function()
      M.stop_session(chat.bufnr)
    end,
  })
end

function M.stop_session(bufnr)
  sessions[bufnr] = nil
end

---Log a message or event to the transcript
---@param chat CodeCompanion.Chat
---@param event table
function M.log_event(chat, event)
  local sess = sessions[chat.bufnr]
  if not sess then
    return
  end

  event.at = now_iso()
  local line = safe_json_encode(event)
  if not line then
    return
  end
  if append_line(sess.paths.jsonl, line) then
    sess.metadata.counts.messages = (sess.metadata.counts.messages or 0) + (event.type == "message" and 1 or 0)
    -- Set title from first user message
    if not sess.first_user_logged and event.type == "message" and event.role == config.constants.USER_ROLE then
      sess.first_user_logged = true
      if (config.chatlog.title or {}).mode ~= "off" then
        local max_len = (config.chatlog.title or {}).max_len or 60
        sess.metadata.title = heuristic_title(event.content or "", max_len)
        write_json(sess.paths.meta, sess.metadata)
      end
    else
      -- Periodically update metadata without spamming writes
      write_json(sess.paths.meta, sess.metadata)
    end
  end
end

function M.list()
  local dir = vim.fs.normalize((config.chatlog or {}).dir)
  ensure_dir(dir)
  local metas = vim.fn.glob(dir .. "/chat_*.meta.json", true, true)
  local items = {}
  for _, path in ipairs(metas) do
    local meta = read_json(path)
    if meta then
      local base = path:gsub("%.meta%.json$", "")
      table.insert(items, {
        title = meta.title or meta.chat_id,
        created_on = meta.created_on,
        adapter = meta.adapter,
        model = meta.model,
        chat_id = meta.chat_id,
        meta_path = path,
        jsonl_path = base .. ".jsonl",
      })
    end
  end
  table.sort(items, function(a, b)
    return (a.created_on or "") > (b.created_on or "")
  end)
  return items
end

function M.rehydrate(item)
  local jsonl = item.jsonl_path or item
  local fd = io.open(jsonl, "r")
  if not fd then
    vim.notify("Failed to read chat log: " .. tostring(jsonl), vim.log.levels.ERROR)
    return nil
  end
  local lines = {}
  for line in fd:lines() do
    table.insert(lines, line)
  end
  fd:close()

  local messages = {}
  for _, line in ipairs(lines) do
    local ok, evt = pcall(vim.json.decode, line)
    if ok and evt and evt.type == "message" then
      if evt.role == config.constants.SYSTEM_ROLE or evt.role == config.constants.USER_ROLE or evt.role == config.constants.LLM_ROLE then
        table.insert(messages, {
          role = evt.role,
          content = evt.content,
          reasoning = evt.reasoning,
          tool_calls = evt.tool_calls,
        })
      end
    end
  end

  local meta = item.meta_path and read_json(item.meta_path) or nil
  local adapter_name = meta and meta.adapter or config.strategies.chat.adapter

  local Chat = require("codecompanion.strategies.chat")
  local adapter = require("codecompanion.adapters").resolve(require("codecompanion.config").adapters[adapter_name])
  local chat = Chat.new({
    adapter = adapter,
    messages = messages,
    from_prompt_library = false,
    last_role = config.constants.USER_ROLE,
    logging = false, -- do not start a new log when rehydrating
    ignore_system_prompt = true, -- avoid adding another system prompt
  })

  if chat and meta then
    pcall(vim.api.nvim_buf_set_var, chat.bufnr, "chat_metadata", meta)
  end
  return chat
end

return M
