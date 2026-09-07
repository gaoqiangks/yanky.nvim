local stub = require("luassert.stub")
local yanky = require("yanky")
local utils = require("yanky.utils")
local highlight = require("yanky.highlight")
local clipboard = require("yanky.system_clipboard")

local function setup(options)
  yanky.setup(vim.tbl_deep_extend("force", {
    ring = { storage = "memory" },
    system_clipboard = { sync_with_ring = false },
  }, options or {}))
  yanky.history.clear()
end

describe("Setup lifecycle", function()
  it("does not accumulate yank autocmds", function()
    setup()
    local count = #vim.api.nvim_get_autocmds({ event = "TextYankPost" })
    for _ = 1, 5 do
      setup()
    end
    assert.are.equal(count, #vim.api.nvim_get_autocmds({ event = "TextYankPost" }))
  end)

  it("removes focus handlers when clipboard sync is disabled", function()
    setup({ system_clipboard = { sync_with_ring = true } })
    setup()
    assert.are.equal(0, #vim.api.nvim_get_autocmds({ group = "YankySyncClipboard" }))
  end)

  it("cancels pending focus reads on reconfiguration", function()
    setup({ system_clipboard = { sync_with_ring = true, clipboard_register = "a" } })
    vim.api.nvim_exec_autocmds("FocusLost", {})
    setup()
    vim.wait(550, function()
      return false
    end)
    assert.is_nil(clipboard.state.reg_info_on_focus_lost)
  end)

  it("closes the previous highlight timer", function()
    setup()
    local timer = highlight.timer
    setup()
    assert.is_true(timer:is_closing())
  end)
end)

describe("Highlight cleanup", function()
  local first, second
  before_each(function()
    setup({ highlight = { timer = 30 } })
    first = vim.api.nvim_create_buf(false, true)
    second = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(first)
    vim.api.nvim_buf_set_lines(first, 0, -1, false, { "text" })
    vim.api.nvim_buf_set_mark(first, "[", 1, 0, {})
    vim.api.nvim_buf_set_mark(first, "]", 1, 2, {})
    vim.fn.setreg("a", "tex", "v")
  end)

  after_each(function()
    vim.api.nvim_buf_delete(first, { force = true })
    vim.api.nvim_buf_delete(second, { force = true })
  end)

  it("clears the original buffer after switching buffers", function()
    highlight.highlight_put({ register = "a" })
    assert.is_true(#vim.api.nvim_buf_get_extmarks(first, highlight.hl_put, 0, -1, {}) > 0)
    vim.api.nvim_set_current_buf(second)
    assert.is_true(vim.wait(300, function()
      return #vim.api.nvim_buf_get_extmarks(first, highlight.hl_put, 0, -1, {}) == 0
    end))
  end)

  it("clears existing marks when highlighting is disabled", function()
    highlight.highlight_put({ register = "a" })
    setup({ highlight = { on_put = false, on_yank = false } })
    assert.are.equal(0, #vim.api.nvim_buf_get_extmarks(first, highlight.hl_put, 0, -1, {}))
  end)
end)

describe("Failure recovery", function()
  before_each(function()
    setup()
  end)

  it("restores a temporary register when the callback fails", function()
    vim.fn.setreg("a", "original", "V")
    assert.has_error(function()
      utils.use_temporary_register("a", { regcontents = "temporary", regtype = "v" }, function()
        error("callback failed")
      end)
    end)
    assert.are.equal("original\n", vim.fn.getreg("a"))
    assert.are.equal("V", vim.fn.getregtype("a"))
  end)

  it("reports invalid special mappings without raising an error", function()
    local notify = stub(vim, "notify")
    local ok, result = pcall(require("yanky.picker").actions.special_put, "NonexistentYankyPlug", false)
    notify:revert()
    assert.is_true(ok)
    assert.is_nil(result)
  end)

  it("does not move the history cursor below zero", function()
    yanky.history.reset()
    assert.is_nil(yanky.history.previous())
    assert.are.equal(0, yanky.history.position)
    yanky.history.push({ regcontents = "first", regtype = "v" })
    assert.are.equal("first", yanky.history.next().regcontents)
  end)

  it("does not attach a scheduled move callback after the ring is cleared", function()
    setup({ ring = { cancel_event = "move" } })
    vim.fn.setreg("a", "text", "v")
    local callback
    local schedule = stub(vim, "schedule", function(fn)
      callback = fn
    end)
    yanky.init_ring("p", "a", 1, false)
    yanky.clear_ring()
    schedule:revert()
    assert.has_no.errors(callback)
    assert.are.equal(0, #vim.api.nvim_get_autocmds({ group = "YankyRingClear" }))
  end)
end)

describe("Buffer listeners", function()
  local buffer, attach, calls
  before_each(function()
    setup()
    buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buffer)
    calls = 0
    attach = vim.api.nvim_buf_attach
    vim.api.nvim_buf_attach = function(...)
      calls = calls + 1
      return attach(...)
    end
  end)

  after_each(function()
    vim.api.nvim_buf_attach = attach
    vim.api.nvim_buf_delete(buffer, { force = true })
  end)

  it("attaches only once for repeated yanks without edits", function()
    local preserve = require("yanky.preserve_cursor")
    for _ = 1, 100 do
      preserve.yank()
      preserve.on_yank()
    end
    assert.are.equal(1, calls)
    preserve.yank()
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "changed" })
    assert.is_nil(preserve.state.cusor_position)
  end)

  it("does not duplicate ring listeners at history boundaries", function()
    vim.fn.setreg("a", "text", "v")
    yanky.init_ring("p", "a", 1, false)
    for _ = 1, 100 do
      yanky.attach_cancel()
    end
    assert.are.equal(1, calls)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "changed" })
    assert.is_false(yanky.can_cycle())
  end)
end)
