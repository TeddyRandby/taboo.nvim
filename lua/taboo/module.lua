local components = require("taboo.components")
local ui = require("taboo.ui")

---@class TabooStateInternal
---@field width integer
local M = {
  width = 5,
}

---Render the taboo ui into its' buffer
---@param taboo TabooState
function M.render(taboo)
  if not ui.haswinnr(taboo) or not ui.hasbufnr(taboo) then
    return
  end

  vim.api.nvim_win_set_width(ui.winnr(taboo, 0), M.width)

  vim.api.nvim_buf_clear_namespace(ui.bufnr(taboo), taboo.nsnr, 0, -1)

  vim.api.nvim_buf_set_lines(ui.bufnr(taboo), 0, -1, false, {"     "})
  vim.api.nvim_buf_add_highlight(ui.bufnr(taboo), taboo.nsnr, "TabooTop", 0, 0, -1)

  for i, _ in ipairs(components.components) do
    components.render(taboo, i)
  end

end

---Toggle the taboo ui window
---@param taboo TabooState
function M.toggle(taboo)
  if ui.haswinnr(taboo) then
    M.close(taboo)
  else
    M.open(taboo)
  end
end

---Open the taboo ui window
---@param taboo TabooState
function M.open(taboo)
  if not ui.hasnsnr(taboo) then
    local nsid = vim.api.nvim_create_namespace("taboo")
    assert(nsid ~= 0, "Failed to create namespace")
    taboo.nsnr = nsid

    ui.nssetup(taboo, taboo.nsnr)
  end

  if not ui.hasbufnr(taboo) then
    local bid = vim.api.nvim_create_buf(false, true)
    assert(bid ~= 0, "Failed to create buffer")

    ui.bufnr(taboo, bid)
    ui.bufsetup(taboo, ui.bufnr(taboo))
  end

  if not ui.haswinnr(taboo) then
    vim.api.nvim_command(M.width .. "vsp")
    vim.api.nvim_command "wincmd H"

    local wid = vim.api.nvim_get_current_win()

    ui.winnr(taboo, 0, wid)
    ui.winsetup(taboo, wid, ui.bufnr(taboo))
  end

  vim.api.nvim_set_current_win(ui.winnr(taboo, 0))
  vim.api.nvim_command "stopinsert"
  M.select(taboo, taboo.selected)
end

---Close the taboo ui window
---@param taboo TabooState
function M.close(taboo)
  if ui.haswinnr(taboo) then
    vim.api.nvim_win_close(ui.winnr(taboo, 0), true)
    ui.winnr(taboo, 0, -1)
  end
end

---Launch the target component
---@param taboo TabooState
---@param target string | integer | nil
function M.launch(taboo, target)
  local cmpnr = target or taboo.selected

  if type(target) == "string" then
    cmpnr = components.find(taboo, target)

    if cmpnr == -1 then
      vim.notify_once("Component not found: " .. target, vim.log.levels.ERROR)
      return
    end
  end

  assert(type(cmpnr) == "number", "Invalid target: Expected number, not " .. vim.inspect(cmpnr))

  components.launch(taboo, cmpnr)

  M.open(taboo)

  components.focus(taboo, cmpnr)
end

---@class TabooSelect
---@field skip boolean?
---@field preview boolean?

---Select the component at index 'i'
---This is 1-based, and will clamp to within the bounds of the component table.
---@param taboo TabooState
---@param cmpnr integer
---@param opts TabooSelect?
function M.select(taboo, cmpnr, opts)
  opts = opts or {}

  if cmpnr > #components.components then
    cmpnr = 1
  end

  if cmpnr < 1 then
    cmpnr = #components.components
  end

  taboo.selected = cmpnr

  local tid = components.tabnr(taboo, 0)

  M.render(taboo)
  M.focus(taboo)

  if opts.preview and components.hastabnr(taboo, 0) and ui.haswinnr(taboo, tid) then
    components.launch(taboo, 0)
    components.focus(taboo, cmpnr, true)
  end
end

---Select the next component
---@param taboo TabooState
---@param tabnr integer?
---@return integer
function M.find_tab(taboo, tabnr)
  if not tabnr then
    return -1
  end

  return components.find_tab(taboo, tabnr)
end

---Select the next component
---@param taboo TabooState
---@param opts TabooSelect?
function M.next(taboo, opts)
  M.select(taboo, taboo.selected + 1, opts)

  if opts and opts.skip then
    local starting_point = taboo.selected

    while not components.hastabnr(taboo, 0) do
      M.select(taboo, taboo.selected + 1, opts)

      if taboo.selected == starting_point then
        break
      end
    end
  end
end

---Select the previous component
---@param taboo TabooState
---@param opts TabooSelect?
function M.prev(taboo, opts)
  M.select(taboo, taboo.selected - 1, opts)

  if opts and opts.skip then
    local starting_point = taboo.selected

    while not components.hastabnr(taboo, 0) do
      M.select(taboo, taboo.selected - 1, opts)

      if taboo.selected == starting_point then
        break
      end
    end
  end
end

---Focus the taboo ui
---@param taboo TabooState
function M.focus(taboo)
  if ui.haswinnr(taboo, 0) then
    vim.api.nvim_set_current_win(ui.winnr(taboo, 0))
  end
end

---Append a component to the list.
---If successful, re-render the ui.
---@param cmp TabooAppend
function M.append(taboo, cmp)
  if components.append(taboo, cmp) then
    M.render(taboo)
  end
end

---Detatch a component from it's tab.
---@param cmp string | integer | nil
function M.detatch(taboo, cmp)
  components.detatch(taboo, cmp)
end

---Remove a component from the list.
---If successful, select the previous component.
---@param cmp string | integer | nil
function M.remove(taboo, cmp)
  local result = components.remove(taboo, cmp)

  if result then
    if #components.components == 0 then
      M.close(taboo)
    end

    if result == taboo.selected then
      M.prev(taboo, true, { enter = true })
    end
  end

  M.render(taboo)
end

---@class TabooLauncherOptions
---@field term boolean?

---@alias TabooLauncher fun(taboo: TabooState, tid: integer, tab: TabooTab)

---Create a launcher for the given command
---@param taboo TabooState
---@param cmd string | function
---@param opts TabooLauncherOptions?
---@return TabooLauncher
function M.launcher(taboo, cmd, opts)
  opts = opts or {}

  return function()
    if type(cmd) == "function" then
      cmd()
    end

    if type(cmd) == "string" then
      if opts.term then
        local set_opts = { win = 0, scope = "local" }
        vim.api.nvim_set_option_value("signcolumn", "no", set_opts)
        vim.api.nvim_set_option_value("relativenumber", false, set_opts)
        vim.api.nvim_set_option_value("number", false, set_opts)

        vim.fn.termopen(cmd, {
          on_exit = function()
            components.detatch(taboo, 0)

            vim.api.nvim_command [[
              bdelete!
              tabclose!
            ]]
          end,
          on_stderr = function(_, data)
            vim.notify_once(data, vim.log.levels.ERROR)
          end,
        })
      end

      if not opts.term then
        vim.api.nvim_command(cmd)
      end
    end
  end
end

return M
