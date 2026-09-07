local utils = {}

-- Execute native editing commands synchronously, without parsing an Ex script.
-- Keeping :normal semantics preserves registers, undo and dot-repeat behavior.
function utils.normal(keys, range)
  vim.api.nvim_cmd({
    cmd = "normal",
    bang = true,
    args = { keys },
    range = range,
    mods = { silent = true },
  }, {})
end

function utils.is_osc52_active()
  if not vim.g.clipboard then
    return false
  end

  -- Per the docs, OSC 52 should be set up with a name field in the table
  if vim.g.clipboard.name == "OSC 52" then
    return true
  end

  return false
end

function utils.get_default_register()
  if utils.is_osc52_active() then
    return '"'
  end

  local clipboard_flags = vim.split(vim.api.nvim_get_option_value("clipboard", {}), ",")
  local selected_register = '"'

  if vim.tbl_contains(clipboard_flags, "unnamed") then
    selected_register = "*"
  end

  if vim.tbl_contains(clipboard_flags, "unnamedplus") then
    selected_register = "+"
  end

  if selected_register ~= '"' then
    local clipboard_tool = vim.fn["provider#clipboard#Executable"]()
    if not clipboard_tool or "" == clipboard_tool then
      return '"'
    end
  end

  return selected_register
end

function utils.get_system_register()
  local clipboard_flags = vim.split(vim.api.nvim_get_option_value("clipboard", {}), ",")

  if vim.tbl_contains(clipboard_flags, "unnamedplus") then
    return "+"
  end
  return "*"
end

function utils.get_register(register)
  register = register or vim.v.register
  if utils.is_osc52_active() and (register == "+" or register == "*") then
    return '"'
  end
  return register
end

function utils.get_register_info(register)
  local ok_contents, regcontents = pcall(vim.fn.getreg, register)
  local ok_type, regtype = pcall(vim.fn.getregtype, register)

  if not ok_contents or not ok_type then
    return nil
  end

  return {
    regcontents = regcontents,
    regtype = regtype,
  }
end

function utils.register_info_from_lines(lines, regtype)
  return {
    regcontents = table.concat(lines, "\n") .. (regtype == "V" and "\n" or ""),
    regtype = regtype,
  }
end

function utils.use_temporary_register(register, register_info, callback)
  local current_register_info = utils.get_register_info(register)
  if not current_register_info then
    error("Unable to read register " .. register)
  end
  vim.fn.setreg(register, register_info.regcontents, register_info.regtype)
  local ok, err = pcall(callback)
  vim.fn.setreg(register, current_register_info.regcontents, current_register_info.regtype)
  if not ok then
    error(err, 0)
  end
end

return utils
