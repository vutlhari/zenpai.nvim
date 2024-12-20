local M = {}

local Menu = require "nui.menu"
local git_cmd = require "zenpai.git_cmd"
local openai = require "zenpai.openai"
local prompts = require "zenpai.prompts"

local function generate_commit()
  if not git_cmd.is_git_repo() then
    vim.notify "not a git repository."
    return
  end

  if not git_cmd.has_changes() then
    vim.notify "no changes to commit."
    return
  end

  local files_to_stage = git_cmd.files_to_be_staged()
  if not files_to_stage then
    return
  end

  local curr_branch = git_cmd.current_branch()
  if curr_branch == "main" or curr_branch == "master" then
    if not git_cmd.create_branch "wip" then
      vim.notify("error checking out new branch.", vim.log.levels.ERROR)
      return
    end
  end

  local prompt_msg = string.format("%s\nstage these files? (y/n): ", files_to_stage)
  local confirm = vim.fn.input(prompt_msg):lower()
  if confirm ~= "y" and confirm ~= "yes" then
    vim.notify "staging aborted."
    return
  end

  git_cmd.stage_files()
  vim.notify "files staged successfully."

  local diff = git_cmd.get_diff()
  local commit_msg_prompt = prompts.commit_msg_prompt(diff)

  openai.completions({
    messages = {
      { role = "system", content = "You are to act as an author of a commit message in git." },
      { role = "user", content = commit_msg_prompt },
    },
  }, function(data)
    vim.schedule(function()
      local commit_msg = data.choices[1].message.content:lower()
      if git_cmd.commit(commit_msg) then
        vim.notify "changes committed successfully."
      else
        vim.notify("error committing changes.", vim.log.levels.ERROR)
      end
    end)
  end, function(err)
    vim.schedule(function()
      vim.notify(err.error.message)
    end)
  end)
end

local function menu_option_selected(item)
  if item.id == 1 then
    generate_commit()
  end
end

local menu = Menu({
  position = "50%",
  size = {
    width = 25,
    height = 5,
  },
  border = {
    style = "single",
    text = {
      top = "[Choose Action]",
      top_align = "center",
    },
  },
  win_options = {
    winhighlight = "Normal:Normal,FloatBorder:Normal",
  },
}, {
  lines = {
    Menu.item("Commit Changes", { id = 1 }),
  },
  max_width = 20,
  keymap = {
    focus_next = { "j", "<Down>", "<Tab>" },
    focus_prev = { "k", "<Up>", "<S-Tab>" },
    close = { "<Esc>", "<C-c>" },
    submit = { "<CR>", "<Space>" },
  },
  on_submit = menu_option_selected,
})

function M.setup(opts)
  opts = opts or {}
  vim.keymap.set("n", "<Leader>i", function()
    menu:mount()
  end)
end

return M
