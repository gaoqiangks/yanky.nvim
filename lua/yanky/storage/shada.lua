local shada = {}

function shada.setup()
  shada.config = require("yanky.config").options.ring
end

function shada.push(item)
  -- Reading vim.g already creates a Lua copy of the Vimscript value.
  local copy = vim.g.YANKY_HISTORY or {}
  table.insert(copy, 1, item)

  if #copy > shada.config.history_length then
    table.remove(copy)
  end

  vim.g.YANKY_HISTORY = copy
end

function shada.get(n)
  return shada.all()[n]
end

function shada.length()
  return #shada.all()
end

function shada.all()
  return vim.g.YANKY_HISTORY or {}
end

function shada.clear()
  vim.g.YANKY_HISTORY = {}
end

function shada.delete(index)
  local copy = vim.g.YANKY_HISTORY or {}
  table.remove(copy, index)

  vim.g.YANKY_HISTORY = copy
end

return shada
