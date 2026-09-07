local utils = require("yanky.utils")

local system_clipboard = {
  state = {
    reg_info_on_focus_lost = nil,
  },
}

local function stop_timer()
  if system_clipboard.timer then
    if not system_clipboard.timer:is_closing() then
      system_clipboard.timer:stop()
      system_clipboard.timer:close()
    end
    system_clipboard.timer = nil
  end
end

function system_clipboard.setup()
  stop_timer()
  local state = { focused = true, focus_lost = false, generation = 0 }
  system_clipboard.state = state
  system_clipboard.config = require("yanky.config").options.system_clipboard
  system_clipboard.config.clipboard_register = system_clipboard.config.clipboard_register or utils.get_system_register()
  system_clipboard.history = require("yanky.history")
  local group = vim.api.nvim_create_augroup("YankySyncClipboard", { clear = true })

  if not system_clipboard.config.sync_with_ring then
    return
  end

  vim.api.nvim_create_autocmd({ "FocusGained", "FocusLost" }, {
    group = group,
    callback = function(ev)
      -- Providers can steal focus; update state before invoking them.
      state.generation = state.generation + 1
      stop_timer()
      if ev.event == "FocusLost" then
        state.focused = false
        local generation = state.generation
        system_clipboard.timer = vim.defer_fn(function()
          if system_clipboard.state ~= state or state.generation ~= generation or state.focused then
            return
          end
          system_clipboard.timer = nil
          state.focus_lost = true
          system_clipboard.on_focus_lost()
        end, 500)
      else
        local sync = state.focus_lost
        state.focused = true
        state.focus_lost = false
        if sync then
          system_clipboard.on_focus_gained()
        end
      end
    end,
  })
end

function system_clipboard.on_focus_lost()
  system_clipboard.state.reg_info_on_focus_lost = utils.get_register_info(system_clipboard.config.clipboard_register)
end

function system_clipboard.on_focus_gained()
  local new_reg_info = utils.get_register_info(system_clipboard.config.clipboard_register)

  if new_reg_info == nil then
    system_clipboard.state.reg_info_on_focus_lost = nil
    return
  end

  if
    system_clipboard.state.reg_info_on_focus_lost ~= nil
    and not vim.deep_equal(system_clipboard.state.reg_info_on_focus_lost, new_reg_info)
  then
    system_clipboard.history.push(new_reg_info)
  end

  system_clipboard.state.reg_info_on_focus_lost = nil
end

return system_clipboard
