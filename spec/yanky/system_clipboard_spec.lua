local yanky = require("yanky")
local clipboard = require("yanky.system_clipboard")
local utils = require("yanky.utils")
local stub = require("luassert.stub")

describe("Clipboard synchronization", function()
  before_each(function()
    yanky.setup({
      ring = { storage = "memory" },
      system_clipboard = { sync_with_ring = true, clipboard_register = "a" },
    })
    yanky.history.clear()
    vim.fn.setreg("a", "original", "v")
  end)

  after_each(function()
    yanky.setup({ ring = { storage = "memory" }, system_clipboard = { sync_with_ring = false } })
  end)

  it("adds changed contents on focus gain", function()
    clipboard.on_focus_lost()
    vim.fn.setreg("a", "changed", "V")
    clipboard.on_focus_gained()
    assert.are.same({ regcontents = "changed\n", regtype = "V" }, yanky.history.first())
    assert.is_nil(clipboard.state.reg_info_on_focus_lost)
  end)

  it("ignores unchanged contents and focus gain without a baseline", function()
    clipboard.on_focus_gained()
    clipboard.on_focus_lost()
    clipboard.on_focus_gained()
    assert.are.equal(0, #yanky.history.all())
  end)

  it("recovers after the provider fails", function()
    clipboard.on_focus_lost()
    local read = stub(utils, "get_register_info", function()
      return nil
    end)
    clipboard.on_focus_gained()
    read:revert()
    assert.is_nil(clipboard.state.reg_info_on_focus_lost)
    assert.are.equal(0, #yanky.history.all())
    clipboard.on_focus_lost()
    vim.fn.setreg("a", "recovered", "v")
    clipboard.on_focus_gained()
    assert.are.equal("recovered", yanky.history.first().regcontents)
  end)

  it("skips clipboard reads during rapid focus changes", function()
    local calls = 0
    local read = stub(utils, "get_register_info", function()
      calls = calls + 1
      return { regcontents = "value", regtype = "v" }
    end)
    for _ = 1, 20 do
      vim.api.nvim_exec_autocmds("FocusLost", {})
      vim.api.nvim_exec_autocmds("FocusGained", {})
    end
    vim.wait(550, function()
      return false
    end)
    read:revert()
    assert.are.equal(0, calls)
  end)

  it("syncs after a sustained focus loss", function()
    vim.api.nvim_exec_autocmds("FocusLost", {})
    assert.is_true(vim.wait(800, function()
      return clipboard.state.reg_info_on_focus_lost ~= nil
    end))
    vim.fn.setreg("a", "external", "v")
    vim.api.nvim_exec_autocmds("FocusGained", {})
    assert.are.equal("external", yanky.history.first().regcontents)
  end)
end)
