local preserve_cursor = { attached_buffers = {} }

preserve_cursor.state = {
  cusor_position = nil,
  win_state = nil,
}

function preserve_cursor.setup()
  preserve_cursor.config = require("yanky.config").options.preserve_cursor_position
  preserve_cursor.state = {}
end

function preserve_cursor.on_yank()
  if not preserve_cursor.config.enabled then
    return
  end

  if nil ~= preserve_cursor.state.cusor_position then
    vim.fn.setpos(".", preserve_cursor.state.cusor_position)
    vim.fn.winrestview(preserve_cursor.state.win_state)

    preserve_cursor.state = {
      cusor_position = nil,
      win_state = nil,
    }
  end
end

function preserve_cursor.yank()
  if not preserve_cursor.config.enabled then
    return
  end

  preserve_cursor.state = {
    cusor_position = vim.fn.getpos("."),
    win_state = vim.fn.winsaveview(),
    buffer = vim.api.nvim_get_current_buf(),
  }

  local buffer = preserve_cursor.state.buffer
  if preserve_cursor.attached_buffers[buffer] then
    return
  end
  preserve_cursor.attached_buffers[buffer] = true
  vim.api.nvim_buf_attach(buffer, false, {
    on_lines = function()
      if preserve_cursor.state.buffer == buffer then
        preserve_cursor.state = {}
      end
    end,
    on_detach = function()
      preserve_cursor.attached_buffers[buffer] = nil
      if preserve_cursor.state.buffer == buffer then
        preserve_cursor.state = {}
      end
    end,
  })
end

return preserve_cursor
