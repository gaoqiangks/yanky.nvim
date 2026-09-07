local history = {
  storage = nil,
  position = 1,
  config = nil,
}

function history.setup()
  history.config = require("yanky.config").options.ring
  history.storage = require("yanky.storage." .. history.config.storage)
  if false == history.storage.setup() then
    history.storage = require("yanky.storage.memory")
    history.storage.setup()
  end
  history.position = 1
end

function history.push(item)
  if item == nil then
    -- `utils.get_register_info` returns nil when the register can't be read
    -- (e.g. a clipboard provider error), so there is nothing to push.
    return
  end

  local prev = history.storage.get(1)
  if prev ~= nil and prev.regcontents == item.regcontents and prev.regtype == item.regtype then
    return
  end

  history.storage.push(item)

  history.sync_with_numbered_registers()
end

function history.sync_with_numbered_registers()
  if history.config.sync_with_numbered_registers then
    local entries = history.storage.all(9)
    for i = 1, math.min(#entries, 9) do
      local reg = entries[i]
      vim.fn.setreg(i, reg.regcontents, reg.regtype)
    end
  end
end

function history.first()
  return history.storage.get(1)
end

function history.skip()
  history.position = history.position + 1
end

function history.next()
  local new_position = history.position + 1
  local item = history.storage.get(new_position)
  if item == nil then
    return nil
  end

  history.position = new_position

  return item
end

function history.previous()
  if history.position <= 1 then
    return nil
  end

  history.position = history.position - 1

  return history.storage.get(history.position)
end

function history.reset()
  history.position = 0
end

function history.all()
  return history.storage.all()
end

function history.clear()
  history.storage.clear()
  history.position = 1
end

function history.delete(index)
  history.storage.delete(index)
end

return history
