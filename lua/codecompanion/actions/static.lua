local codecompanion = require("codecompanion")
local config = require("codecompanion.config")

local function send_code(context)
  local text = require("codecompanion.helpers.actions").get_code(context.start_line, context.end_line)

  return "I have the following code:\n\n```" .. context.filetype .. "\n" .. text .. "\n```\n\n"
end

return {
  {
    name = "Chat",
    strategy = "chat",
    description = "Create a new chat buffer to converse with an LLM",
    type = nil,
    opts = {
      index = 1,
      stop_context_insertion = true,
    },
    prompts = {
      n = function()
        return codecompanion.chat()
      end,
      v = {
        {
          role = config.constants.SYSTEM_ROLE,
          content = function(context)
            return "I want you to act as a senior "
              .. context.filetype
              .. " developer. I will give you specific code examples and ask you questions. I want you to advise me with explanations and code examples."
          end,
        },
        {
          role = config.constants.USER_ROLE,
          content = function(context)
            return send_code(context)
          end,
          opts = {
            contains_code = true,
          },
        },
      },
    },
  },
  {
    name = "Open chats ...",
    strategy = " ",
    description = "Your currently open chats",
    opts = {
      index = 2,
      stop_context_insertion = true,
    },
    condition = function()
      return #codecompanion.buf_get_chat() > 0
    end,
    picker = {
      prompt = "Select a chat",
      items = function()
        local loaded_chats = codecompanion.buf_get_chat()
        local open_chats = {}

        for _, data in ipairs(loaded_chats) do
          table.insert(open_chats, {
            name = data.name,
            strategy = "chat",
            description = data.description,
            bufnr = data.chat.bufnr,
            callback = function()
              codecompanion.close_last_chat()
              data.chat.ui:open()
            end,
          })
        end

        return open_chats
      end,
    },
  },

{
  name = "Open Historic Chats",
  strategy = "",
  description = "Browse historic chat logs",
  opts = {
    index = 3,
    stop_context_insertion = true,
  },
  picker = {
    prompt = "Select historic chat:",
    items = function()
      local log_dir = vim.fn.expand("~/codecompanion_chats/")
      local pattern = log_dir .. "/chat_*.txt"
      local files_str = vim.fn.glob(pattern, 1)
      if files_str == "" then
        return {}  -- No historic chat logs found.
      end
      local files = vim.split(files_str, "\n")
      local items = {}
      for _, file in ipairs(files) do
        table.insert(items, {
          name = vim.fn.fnamemodify(file, ":t"),
          callback = function()
            local meta_file = file:gsub("%.txt$", ".metadata")
            local meta_fd = io.open(meta_file, "r")
            local metadata = {}
            if meta_fd then
              local meta_content = meta_fd:read("*a")
              metadata = vim.fn.json_decode(meta_content)
              meta_fd:close()
            else
              vim.notify("No metadata found for " .. file, vim.log.levels.WARN)
            end
            local log_fd = io.open(file, "r")
            if not log_fd then
              vim.notify("Failed to read chat log: " .. file, vim.log.levels.ERROR)
              return
            end
            local chat_log = log_fd:read("*a")
            log_fd:close()
            local Chat = require("codecompanion.strategies.chat")
            local chat = Chat.rehydrate(chat_log, metadata)
            if chat then
              vim.notify("Rehydrated historic chat: " .. vim.fn.fnamemodify(file, ":t"))
            else
              vim.notify("Failed to rehydrate historic chat", vim.log.levels.ERROR)
            end
          end,
        })
      end
      return items
    end,
  },
},

}
