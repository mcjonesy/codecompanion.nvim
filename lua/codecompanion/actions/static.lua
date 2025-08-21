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
      local chatlog = require("codecompanion.chatlog")
      local items = {}
      for _, it in ipairs(chatlog.list()) do
        table.insert(items, {
          name = (it.title or it.chat_id),
          callback = function()
            local chat = chatlog.rehydrate(it)
            if chat then
              vim.notify("Rehydrated historic chat: " .. (it.title or it.chat_id))
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
