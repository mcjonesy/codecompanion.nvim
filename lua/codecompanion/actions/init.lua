local Strategy = require("codecompanion.strategies")
local config = require("codecompanion.config")
local prompt_library = require("codecompanion.actions.prompt_library")
local static_actions = require("codecompanion.actions.static")

local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")

---@class CodeCompanion.Actions
local Actions = {}

local _cached_actions = {}

---Validate the items against the context to determine their visibility
---@param items table The items to validate
---@param context table The buffer context
---@return table
function Actions.validate(items, context)
  local validated_items = {}
  local mode = context.mode:lower()

  for _, item in ipairs(items) do
    if item.condition and type(item.condition) == "function" then
      if item.condition(context) then
        table.insert(validated_items, item)
      end
    elseif item.opts and item.opts.modes then
      if util.contains(item.opts.modes, mode) then
        table.insert(validated_items, item)
      end
    else
      table.insert(validated_items, item)
    end
  end

  return validated_items
end

---Resolve the actions to display in the menu
---@param context table The buffer context
---@return table
function Actions.items(context)
  if not next(_cached_actions) then
    if config.display.action_palette.opts.show_default_actions then
      for _, action in ipairs(static_actions) do
        table.insert(_cached_actions, action)
      end
    end

    if config.prompt_library and not vim.tbl_isempty(config.prompt_library) then
      local prompts = prompt_library.resolve(context, config)
      for _, prompt in ipairs(prompts) do
        table.insert(_cached_actions, prompt)
      end
    end
  end

  return Actions.validate(_cached_actions, context)
end

---Resolve the selected item into a strategy
---@param item table
---@param context table
---@return nil
function Actions.resolve(item, context)
  return Strategy.new({
    context = context,
    selected = item,
  }):start(item.strategy)
end

---Launch the action palette
---@param context table The buffer context
---@param args? { name: string, opts: table } The provider to use
---@return nil
function Actions.launch(context, args)
  local items = Actions.items(context)

  if items and #items == 0 then
    return log:warn("No prompts available. Please create some in your config or turn on the prompt library")
  end

  -- Resolve for a specific provider
  local provider = config.display.action_palette.provider
  local provider_opts = {}
  if args and args.provider and args.provider.name then
    provider = args.provider.name
    provider_opts = args.provider.opts or {}
  end

  return require("codecompanion.providers.actions." .. provider)
    .new({ context = context, validate = Actions.validate, resolve = Actions.resolve })
    :picker(items, provider_opts)
end

function Actions.open_historic_chat()
  local log_dir = vim.fn.expand("~/codecompanion_chats/")
  local pattern = log_dir .. "/chat_*.txt"
  local files_str = vim.fn.glob(pattern, 1)
  if files_str == "" then
    vim.notify("No historic chats found", vim.log.levels.INFO)
    return
  end
  local files = vim.split(files_str, "\n")
  local chat_list = {}
  for _, file in ipairs(files) do
    local name = vim.fn.fnamemodify(file, ":t")
    table.insert(chat_list, { label = name, path = file })
  end
  vim.ui.select(chat_list, { prompt = "Select historic chat:" }, function(choice)
    if not choice then return end
    local meta_file = choice.path:gsub("%.txt$", ".metadata")
    local meta_fd = io.open(meta_file, "r")
    local metadata = {}
    if meta_fd then
      local meta_content = meta_fd:read("*a")
      metadata = vim.fn.json_decode(meta_content)
      meta_fd:close()
    else
      vim.notify("No metadata found for " .. choice.path, vim.log.levels.WARN)
    end
    local log_fd = io.open(choice.path, "r")
    if not log_fd then
      vim.notify("Failed to read chat log: " .. choice.path, vim.log.levels.ERROR)
      return
    end
    local chat_log = log_fd:read("*a")
    log_fd:close()
    local Chat = require("codecompanion.strategies.chat")
    local chat = Chat.rehydrate(chat_log, metadata)
    if chat then
      vim.notify("Rehydrated historic chat: " .. choice.label)
    else
      vim.notify("Failed to rehydrate historic chat", vim.log.levels.ERROR)
    end
  end)
end

return Actions
